import importlib.util
from pathlib import Path
import boto3
from fastapi.testclient import TestClient
from moto import mock_aws
import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("brain_tasks_api", ROOT / "api/app.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


@pytest.fixture
def client(monkeypatch):
    # Fake credentials remain inside the isolated test process; Moto intercepts AWS calls.
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("AWS_REGION", "ap-south-1")
    monkeypatch.setenv("TASKS_TABLE_NAME", "test-brain-tasks")
    monkeypatch.delenv("DYNAMODB_ENDPOINT", raising=False)
    with mock_aws():
        boto3.client("dynamodb", region_name="ap-south-1").create_table(
            TableName="test-brain-tasks", BillingMode="PAY_PER_REQUEST",
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}, {"AttributeName": "sk", "KeyType": "RANGE"}],
            AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}, {"AttributeName": "sk", "AttributeType": "S"}],
        )
        with TestClient(module.app) as test_client:
            yield test_client


def test_create_read_update_delete_persists_in_dynamodb(client):
    assert client.get("/readyz").status_code == 200
    assert client.get("/api/v1/tasks").json() == []
    created = client.post("/api/v1/tasks", json={"title": "Revise Linux", "description": "Permissions lab", "completed": "Priority"})
    assert created.status_code == 201
    task = created.json()
    assert task["id"].isdigit() and int(task["id"]) <= 9007199254740991
    assert "pk" not in task and "sk" not in task
    assert client.get(f"/api/v1/tasks/{task['id']}").json() == task
    assert client.get("/api/v1/tasks").json() == [task]
    updated = client.put(f"/api/v1/tasks/{task['id']}", json={"title": "Linux done", "description": "Lab verified", "completed": "Completed"})
    assert updated.status_code == 200
    assert updated.json()["createdAt"] == task["createdAt"]
    assert client.get("/api/v1/tasks").json()[0]["completed"] == "Completed"
    assert client.delete(f"/api/v1/tasks/{task['id']}").status_code == 204
    assert client.get("/api/v1/tasks").json() == []


def test_update_missing_task_does_not_silently_create_it(client):
    assert client.get("/api/v1/tasks/missing").status_code == 404
    assert client.put("/api/v1/tasks/missing", json={"title": "Unexpected"}).status_code == 404
    assert client.delete("/api/v1/tasks/missing").status_code == 404
    assert client.get("/api/v1/tasks").json() == []


@pytest.mark.parametrize("payload", [{}, {"title": "   "}, {"title": "x" * 121},
                                      {"title": "Valid", "description": "x" * 2001},
                                      {"title": "Valid", "completed": "invalid"}])
def test_invalid_payload_is_rejected(client, payload):
    assert client.post("/api/v1/tasks", json=payload).status_code == 422
    assert client.get("/api/v1/tasks").json() == []


def test_readiness_detects_missing_table_without_exposing_aws_error(client):
    boto3.client("dynamodb", region_name="ap-south-1").delete_table(TableName="test-brain-tasks")
    response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json() == {"detail": "Task storage is temporarily unavailable"}
