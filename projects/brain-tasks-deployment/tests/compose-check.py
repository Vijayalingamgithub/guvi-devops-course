"""Exercise real container CRUD through Nginx with an isolated local DynamoDB."""
import base64
import json
from pathlib import Path
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:3000"
AUTH = "Basic " + base64.b64encode(b"vijay:ci-validation-password").decode()


def request(method, path, payload=None, authenticated=True):
    headers = {"Content-Type": "application/json"}
    if authenticated:
        headers["Authorization"] = AUTH
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            body = response.read()
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as exc:
        return exc.code, None


def main():
    assert request("GET", "/api/v1/tasks", authenticated=False)[0] == 401
    status, tasks = request("GET", "/api/v1/tasks")
    assert status == 200 and tasks == [], "Expected the isolated in-memory test database"
    status, task = request("POST", "/api/v1/tasks", {
        "title": "Compose integration task", "description": "Disposable CI data", "completed": "Pending"
    })
    assert status == 201 and task["id"].isdigit()
    path = "/api/v1/tasks/" + task["id"]
    assert request("GET", path)[1]["title"] == "Compose integration task"
    assert request("GET", "/api/v1/tasks")[1][0]["id"] == task["id"]
    status, updated = request("PUT", path, {
        "title": "Updated container task", "description": "Disposable CI data", "completed": "Completed"
    })
    assert status == 200 and updated["completed"] == "Completed"
    assert request("DELETE", path)[0] == 204
    assert request("GET", path)[0] == 404
    assert request("GET", "/api/v1/tasks")[1] == []
    result = {"result": "PASS", "runtime": "Docker Compose", "checks": [
        "API authentication", "empty local database", "create", "read", "list", "update", "delete", "missing task"
    ]}
    Path("out").mkdir(exist_ok=True)
    Path("out/compose-validation.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
