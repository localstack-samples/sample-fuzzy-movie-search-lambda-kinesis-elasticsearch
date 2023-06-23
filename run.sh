#!/usr/bin/env bash
# fail on errors, disabled for debugging action pipeline
# set -eo pipefail
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
echo show terraform output ... 
echo $ingest_function_url
echo $elasticsearch_endpoint
echo $(ingest_function_url)
echo $(elasticsearch_endpoint)
echo $$ingest_function_url
echo $$elasticsearch_endpoint

# download the dataset
temp_dir=$(mktemp --directory)
echo "Downloading Movie Dataset..."
movie_dataset_url="https://docs.aws.amazon.com/opensearch-service/latest/developerguide/samples/sample-movies.zip"
curl -L $movie_dataset_url > $temp_dir/sample-movies.zip
unzip $temp_dir/sample-movies.zip -d $temp_dir/

# remove the bulk insert instructions (lines starting with index info) from the bulk import file
# (we want to stream the data in there, instead of using the bulk import)
echo "Pre-processing Movie Dataset..."
grep -v '^{ "index"' $temp_dir/sample-movies.bulk > $temp_dir/sample-movies-processed.bulk
mv $temp_dir/sample-movies-processed.bulk $temp_dir/sample-movies.bulk

echo "Invoking function for each movie..."
while read line
do
   echo -n "."
   echo $line | curl -s -X POST $ingest_function_url \
        -H 'Content-Type: application/json' \
        -d @- > /dev/null
done < $temp_dir/sample-movies.bulk

echo ""
echo "Testing a search query:"

echo ö/$elasticsearch_endpoint/ö/movies/_search
echo  curl -X POST $elasticsearch_endpoint/movies/_search -H "Content-Type: application/json" -d \
 '{
   "query": {
     "multi_match": {
       "fields":  [ "title", "directors", "actors" ],
       "query":     "Tarantino",
       "fuzziness": "AUTO",
       "type": "best_fields"
     }
   }
 }'
# Send a sample fuzzy query
result=$(curl -X POST $elasticsearch_endpoint/movies/_search -H "Content-Type: application/json" -d \
 '{
   "query": {
     "multi_match": {
       "fields":  [ "title", "directors", "actors" ],
       "query":     "Tarantino",
       "fuzziness": "AUTO",
       "type": "best_fields"
     }
   }
 }')
echo $result | jq

# Rudimentary smoke test
hits=$(echo $result | jq .hits.total.value)
if [[ $hits -lt 1 ]]; then
  echo "We have no hits on our query."
  exit 1
fi