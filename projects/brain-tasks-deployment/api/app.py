"""Owned task API; exposed through the password-protected Nginx frontend only."""
from datetime import datetime, timezone
import logging
import os
from typing import Literal

import boto3
from boto3.dynamodb.conditions import Key
from botocore.config import Config
from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator

app = FastAPI(title="Brain Tasks API", docs_url=None, redoc_url=None, openapi_url=None)
logger = logging.getLogger("uvicorn.error")


class TaskInput(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=2000)
    completed: Literal["Pending", "Completed", "Priority"] = "Pending"

    @field_validator("title")
    @classmethod
    def nonblank_title(cls, value):
        value = value.strip()
        if not value:
            raise ValueError("Title cannot be blank")
        return value


def table():
    endpoint = os.environ.get("DYNAMODB_ENDPOINT")
    resource = boto3.resource(
        "dynamodb", region_name=os.environ.get("AWS_REGION", "ap-south-1"),
        endpoint_url=endpoint,
        config=Config(connect_timeout=2, read_timeout=3, retries={"max_attempts": 2}),
    )
    return resource.Table(os.environ["TASKS_TABLE_NAME"])


def task_key(task_id):
    return {"pk": "TASKS", "sk": "TASK#" + task_id}


def public(item):
    return {k: v for k, v in item.items() if k not in {"pk", "sk"}}


@app.exception_handler(ClientError)
async def aws_error(_request, exc):
    logger.error("Task storage request failed: %s", exc.response.get("Error", {}).get("Code", "unknown"))
    return JSONResponse(status_code=503, content={"detail": "Task storage is temporarily unavailable"})


@app.get("/healthz")
def health():
    return {"status": "ok"}


@app.get("/readyz")
def ready():
    result = table().meta.client.describe_table(TableName=os.environ["TASKS_TABLE_NAME"])
    if result["Table"]["TableStatus"] != "ACTIVE":
        raise HTTPException(503, "Task table is not active")
    return {"status": "ready"}


@app.get("/api/v1/tasks")
def list_tasks():
    store = table()
    result = store.query(KeyConditionExpression=Key("pk").eq("TASKS"), ConsistentRead=True)
    items = result.get("Items", [])
    while result.get("LastEvaluatedKey"):
        result = store.query(KeyConditionExpression=Key("pk").eq("TASKS"),
                             ConsistentRead=True, ExclusiveStartKey=result["LastEvaluatedKey"])
        items.extend(result.get("Items", []))
    return sorted([public(item) for item in items], key=lambda item: item["createdAt"], reverse=True)


@app.post("/api/v1/tasks", status_code=201)
def create_task(payload: TaskInput):
    # The supplied frontend converts edit-route IDs to JavaScript Number.
    # An atomic DynamoDB counter keeps IDs numeric and unique across replicas.
    store = table()
    counter = store.update_item(
        Key={"pk": "METADATA", "sk": "TASK_ID"},
        UpdateExpression="ADD #counter :increment",
        ConditionExpression="attribute_not_exists(#counter) OR #counter < :maximum",
        ExpressionAttributeNames={"#counter": "counter"},
        ExpressionAttributeValues={":increment": 1, ":maximum": 9007199254740991},
        ReturnValues="UPDATED_NEW",
    )
    task_id = str(int(counter["Attributes"]["counter"]))
    item = {**task_key(task_id), "id": task_id,
            "createdAt": datetime.now(timezone.utc).isoformat(), **payload.model_dump()}
    store.put_item(Item=item, ConditionExpression="attribute_not_exists(pk)")
    return public(item)


@app.get("/api/v1/tasks/{task_id}")
def get_task(task_id: str):
    item = table().get_item(Key=task_key(task_id), ConsistentRead=True).get("Item")
    if item is None:
        raise HTTPException(404, "Task not found")
    return public(item)


@app.put("/api/v1/tasks/{task_id}")
def update_task(task_id: str, payload: TaskInput):
    try:
        result = table().update_item(
            Key=task_key(task_id), ConditionExpression="attribute_exists(pk)",
            UpdateExpression="SET #title = :title, #description = :description, #completed = :completed",
            ExpressionAttributeNames={"#title": "title", "#description": "description", "#completed": "completed"},
            ExpressionAttributeValues={":" + key: value for key, value in payload.model_dump().items()},
            ReturnValues="ALL_NEW",
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise HTTPException(404, "Task not found") from exc
        raise
    return public(result["Attributes"])


@app.delete("/api/v1/tasks/{task_id}", status_code=204)
def delete_task(task_id: str):
    try:
        table().delete_item(Key=task_key(task_id), ConditionExpression="attribute_exists(pk)")
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            raise HTTPException(404, "Task not found") from exc
        raise
    return Response(status_code=204)
