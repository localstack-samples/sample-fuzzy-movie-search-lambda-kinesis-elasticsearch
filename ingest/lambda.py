import os
import logging
import boto3
import json

logger = logging.getLogger(__name__)


def handler(event, _):
    try:
        kinesis = boto3.client(
            "kinesis", region_name=os.environ["AWS_REGION"], verify=False
        )
        stream_name = os.environ['STREAM_NAME']

        # just directly forward the JSON event body to the Kinesis stream
        kinesis.put_record(StreamName=stream_name, Data=json.dumps(event["body"]), PartitionKey="1")

        logger.info("Put record in stream %s.", stream_name)
    except Exception:
        logger.exception("Sending record to kinesis failed.")
    
    return {"body": "Thanks!"}
