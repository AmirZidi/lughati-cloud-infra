import json
import os
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    try:
        body = json.loads(event["body"])

        course = {
            "id": str(uuid.uuid4()),
            "title": body["title"],
            "language": body["language"],
            "level": body["level"],
            "description": body["description"],
            "createdAt": datetime.utcnow().isoformat(),
        }

        table.put_item(Item=course)

        return {
            "statusCode": 201,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps({"message": "Course created", "course": course}),
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "headers": {"Access-Control-Allow-Origin": "*"},
            "body": json.dumps({"error": str(e)}),
        }
