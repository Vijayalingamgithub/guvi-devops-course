#!/usr/bin/env bash
set -euo pipefail
image="${1:?Usage: bash scripts/smoke-test.sh IMAGE}"
auth_dir="$(mktemp -d)"
printf 'smoke:%s\n' "$(printf '%s\n' 'local-smoke-password' | openssl passwd -6 -stdin)" > "$auth_dir/htpasswd"
chmod 644 "$auth_dir/htpasswd"
container_id="$(docker run -d --read-only --cap-drop ALL \
  --security-opt no-new-privileges --tmpfs /tmp:rw,noexec,nosuid,size=32m \
  --mount "type=bind,src=$auth_dir/htpasswd,dst=/etc/nginx/auth/htpasswd,readonly" \
  -p 127.0.0.1::3000 "$image")"
cleanup() { docker logs "$container_id"; docker rm -f "$container_id" >/dev/null; rm -rf "$auth_dir"; }
trap cleanup EXIT
port="$(docker port "$container_id" 3000/tcp | head -n 1 | awk -F: '{print $NF}')"
base="http://127.0.0.1:$port"
for _attempt in {1..30}; do
  if curl --fail --silent "$base/healthz" >/dev/null; then break; fi
  sleep 1
done
curl --fail --silent "$base/healthz" | grep -qx ok
[[ "$(curl --silent -o /dev/null -w '%{http_code}' "$base/")" = 401 ]]
[[ "$(curl --silent -o /dev/null -w '%{http_code}' "$base/api/v1/tasks")" = 401 ]]
curl --user smoke:local-smoke-password --fail --silent "$base/" | grep -q '<div id="root"></div>'
curl --user smoke:local-smoke-password --fail --silent "$base/createTask" | grep -q '<div id="root"></div>'
[[ "$(curl --user smoke:local-smoke-password --silent -o /dev/null -w '%{http_code}' "$base/assets/missing.js")" = 404 ]]
curl --user smoke:local-smoke-password --fail --silent -D - -o /dev/null "$base/" | grep -iq 'X-Content-Type-Options: nosniff'
[[ "$(docker inspect -f '{{.Config.User}}' "$container_id")" = 101:101 ]]
echo 'PASS: container, health check, React routes, missing asset handling, security header, nonroot user'
