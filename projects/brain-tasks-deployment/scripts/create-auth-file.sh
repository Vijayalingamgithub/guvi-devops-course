#!/usr/bin/env bash
set -euo pipefail
destination="${1:-.local/htpasswd}"
username="${AUTH_USERNAME:-vijay}"
[[ "$username" =~ ^[a-zA-Z0-9_.-]+$ ]] || { echo 'Invalid username'; exit 1; }
if [[ -z "${AUTH_PASSWORD:-}" ]]; then
  read -rs -p 'Set the application password (at least 12 characters): ' AUTH_PASSWORD
  printf '\n'
fi
[[ ${#AUTH_PASSWORD} -ge 12 && "$AUTH_PASSWORD" != *$'\n'* ]] || { echo 'Use at least 12 characters and no newlines'; exit 1; }
mkdir -p "$(dirname "$destination")"
chmod 700 "$(dirname "$destination")"
hash="$(printf '%s\n' "$AUTH_PASSWORD" | openssl passwd -6 -stdin)"
printf '%s:%s\n' "$username" "$hash" > "$destination"
# The containing directory is private. The mounted file must be readable by Nginx's nonroot UID.
chmod 644 "$destination"
unset AUTH_PASSWORD hash
echo "Created the authentication file for user $username"
