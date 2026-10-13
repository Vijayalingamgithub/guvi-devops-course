"""Initialize the in-memory Docker Compose DynamoDB; never create tables in AWS."""
import os
import time
import boto3
from botocore.exceptions import ClientError, EndpointConnectionError

endpoint = os.environ["DYNAMODB_ENDPOINT"]
assert endpoint == "http://dynamodb:8000", "This initializer is for the local Compose service only"
client = boto3.client("dynamodb", endpoint_url=endpoint, region_name="ap-south-1")
for attempt in range(30):
    try:
        client.create_table(
            TableName=os.environ["TASKS_TABLE_NAME"],
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}, {"AttributeName": "sk", "KeyType": "RANGE"}],
            AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}, {"AttributeName": "sk", "AttributeType": "S"}],
            BillingMode="PAY_PER_REQUEST",
        )
        break
    except EndpointConnectionError:
        time.sleep(1)
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ResourceInUseException":
            break
        raise
else:
    raise RuntimeError("Local DynamoDB did not become available")
