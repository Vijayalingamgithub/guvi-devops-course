#!/usr/bin/env bash
set -euo pipefail
image="${1:?Usage: bash scripts/browser-test.sh FRONTEND_IMAGE}"
browser_dir="$(mktemp -d)"
auth_dir="$(mktemp -d)"
container_id=""
cleanup() {
  if [[ -n "$container_id" ]]; then docker rm -f "$container_id" >/dev/null; fi
  rm -rf "$browser_dir" "$auth_dir"
}
trap cleanup EXIT
npm install --prefix "$browser_dir" --no-save playwright@1.62.1 >/dev/null
node "$browser_dir/node_modules/playwright/cli.js" install --with-deps chromium
printf 'smoke:%s\n' "$(printf '%s\n' 'local-smoke-password' | openssl passwd -6 -stdin)" > "$auth_dir/htpasswd"
chmod 644 "$auth_dir/htpasswd"
container_id="$(docker run -d --read-only --cap-drop ALL --security-opt no-new-privileges \
  --tmpfs /tmp:rw,noexec,nosuid,size=32m \
  --mount "type=bind,src=$auth_dir/htpasswd,dst=/etc/nginx/auth/htpasswd,readonly" \
  -p 127.0.0.1::3000 "$image")"
port="$(docker port "$container_id" 3000/tcp | head -n 1 | awk -F: '{print $NF}')"
export BROWSER_TEST_URL="http://127.0.0.1:$port"
for _attempt in {1..30}; do
  if curl --fail --silent "$BROWSER_TEST_URL/healthz" >/dev/null; then break; fi
  sleep 1
done
NODE_PATH="$browser_dir/node_modules" node tests/browser-check.cjs
