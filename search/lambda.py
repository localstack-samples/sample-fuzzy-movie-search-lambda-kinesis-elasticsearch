import os
import logging
import json
import urllib.parse
import urllib.request

logger = logging.getLogger(__name__)


def handler(event, _):
    if not "queryStringParameters" in event or "q" not in event['queryStringParameters']:
        return {'statusCode': 400, 'body': 'Mandatory query parameter "q" missing.'}

    # Extract query parameter "q" from the event
    query = event['queryStringParameters']['q']

    # Define the fuzzy search query
    search_query = {
       "query": {
         "multi_match": {
           "fields":  [ "title", "directors", "actors" ],
           "query":   query,
           "fuzziness": "AUTO",
           "type": "best_fields"
         }
       }
     }

    # Convert search query to JSON string
    search_query_json = json.dumps(search_query).encode('utf-8')
    endpoint = os.environ['ELASTICSEARCH_ENDPOINT']
    index = 'movies'
    url = f'http://{endpoint}/{index}/_search'
    headers = {
        'Content-Type': 'application/json'
    }

    # Sign the request
    # TODO sign the request here!

    # Perform the fuzzy search using REST API
    req = urllib.request.Request(url, data=search_query_json, headers=headers)
    response = urllib.request.urlopen(req)
    result = json.loads(response.read().decode('utf-8'))

    # Extract relevant information from the search result
    movies = []
    if 'hits' in result and 'hits' in result['hits']:
        for hit in result['hits']['hits']:
            movie = {
                '_search_id': hit['_id'],
                '_search_score': hit['_score'],
            } | hit['_source']
            movies.append(movie)

    # Return the search result as a JSON response
    response = {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(movies)
    }
    return response
