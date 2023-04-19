#!/usr/bin/env bash
# fail on errors
set -eo pipefail
# enable alias in script
shopt -s expand_aliases

if [ $# -eq 1 ] && [ $1 = "aws" ]; then
  echo "Deploying on AWS."
else
  echo "Deploying on LocalStack."
  alias aws='awslocal'
  alias terraform='tflocal'
fi

# Start deployment
terraform init; terraform plan; terraform apply --auto-approve
ingest_function_url=$(terraform output --raw ingest_lambda_url)
elasticsearch_endpoint=$(terraform output --raw elasticsearch_endpoint)

# download the dataset
temp_dir=$(mktemp --directory)
echo "Downloading Movie Dataset..."
movie_dataset_url="https://docs.aws.amazon.com/opensearch-service/latest/developerguide/samples/sample-movies.zip"
curl -L $movie_dataset_url > $temp_dir/sample-movies.zip
unzip $temp_dir/sample-movies.zip -d $temp_dir/

# remove the bulk insert instructions (lines starting with index info) from the bulk import file
# (we want to stream the data in there, instead of using the bulk import)
echo "Pre-processing Movie Dataset..."
sed -i '/^{ "index"/d' $temp_dir/sample-movies.bulk

echo "Invoking function for each movie..."
cat $temp_dir/sample-movies.bulk | while read line
do
   echo -n "."
   echo $line | curl -s -X POST $ingest_function_url \
        -H 'Content-Type: application/json' \
        -d @- > /dev/null
done

echo ""
echo "Testing a search query:"

# Send a sample fuzzy query
curl -X POST $elasticsearch_endpoint/movies/_search -H "Content-Type: application/json" -d \
 '{
   "query": {
     "multi_match": {
       "fields":  [ "title", "directors", "actors" ],
       "query":     "Tarantino",
       "fuzziness": "AUTO",
       "type": "best_fields"
     }
   }
 }' | jq