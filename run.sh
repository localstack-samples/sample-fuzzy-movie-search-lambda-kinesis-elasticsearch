#!/usr/bin/env bash
# fail on errors
set -eo pipefail
# enable alias in script
shopt -s expand_aliases

if [ $# -eq 1 ] && [ $1 = "aws" ]; then
  echo "Deploying on AWS."
  alias awslocal='aws'
  alias tflocal='terraform'
else
  echo "Deploying on LocalStack."
fi

# Start deployment
tflocal init; tflocal plan; tflocal apply --auto-approve
ingest_function_url=$(tflocal output --raw ingest_lambda_url)
elasticsearch_endpoint=$(tflocal output --raw elasticsearch_endpoint)

# download the dataset
temp_dir=$(mktemp --directory)
echo "Downloading Movie Dataset..."
movie_dataset_url="https://docs.aws.amazon.com/opensearch-service/latest/developerguide/samples/sample-movies.zip"
curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "$movie_dataset_url" -o "$temp_dir/sample-movies.zip"
unzip -o "$temp_dir/sample-movies.zip" -d "$temp_dir/"

source_bulk_file=$(find "$temp_dir" -maxdepth 2 -type f -name "sample-movies.bulk" | head -n 1)
if [[ -z "$source_bulk_file" ]]; then
  echo "Unable to locate sample-movies.bulk after unzipping dataset."
  exit 1
fi
if [[ "$source_bulk_file" != "$temp_dir/sample-movies.bulk" ]]; then
  cp "$source_bulk_file" "$temp_dir/sample-movies.bulk"
fi

# remove the bulk insert instructions (lines starting with index info) from the bulk import file
# (we want to stream the data in there, instead of using the bulk import)
echo "Pre-processing Movie Dataset..."
awk '!/^{ "index"/' "$temp_dir/sample-movies.bulk" > "$temp_dir/sample-movies-processed.bulk"
mv "$temp_dir/sample-movies-processed.bulk" "$temp_dir/sample-movies.bulk"

echo "Invoking function for each movie..."
while IFS= read -r line
do
   echo -n "."
   printf '%s' "$line" | curl -s -X POST "$ingest_function_url" \
        -H 'Content-Type: application/json' \
        -d @- > /dev/null
done < "$temp_dir/sample-movies.bulk"

echo ""
echo "Testing a search query:"
search_payload='{
  "query": {
    "multi_match": {
      "fields": [ "title", "directors", "actors" ],
      "query": "Tarantino",
      "fuzziness": "AUTO",
      "type": "best_fields"
    }
  }
}'

# Wait for asynchronous Kinesis + Firehose delivery/indexing before failing.
max_attempts=20
retry_delay=5
attempt=1
hits=0

while [[ $attempt -le $max_attempts ]]; do
  result=$(curl -s -X POST "$elasticsearch_endpoint/movies/_search" \
    -H "Content-Type: application/json" \
    -d "$search_payload")

  hits=$(echo "$result" | jq -r '.hits.total.value // 0' 2>/dev/null || echo 0)
  if [[ "$hits" =~ ^[0-9]+$ ]] && [[ "$hits" -ge 1 ]]; then
    break
  fi

  echo "Query attempt $attempt/$max_attempts returned no hits yet; waiting ${retry_delay}s..."
  sleep "$retry_delay"
  attempt=$((attempt + 1))
done

echo "$result" | jq

if [[ ! "$hits" =~ ^[0-9]+$ ]] || [[ "$hits" -lt 1 ]]; then
  echo "No hits found after waiting for indexing."
  exit 1
fi
