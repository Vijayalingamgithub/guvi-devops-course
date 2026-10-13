#!/bin/sh
set -eu
api_upstream="${API_UPSTREAM:-brain-tasks-api.brain-tasks.svc.cluster.local:8000}"
dns_resolver="${DNS_RESOLVER:-$(awk '$1 == "nameserver" {print $2; exit}' /etc/resolv.conf)}"
case "$api_upstream" in *[!a-zA-Z0-9.:-]*|'') echo 'Invalid API_UPSTREAM' >&2; exit 1;; esac
case "$dns_resolver" in *[!0-9a-fA-F.:]*|'') echo 'Invalid DNS resolver' >&2; exit 1;; esac
# Nginx must receive the literal $api_upstream variable name.
# shellcheck disable=SC2016
printf 'resolver %s valid=30s; set $api_upstream "http://%s";\n' \
  "$dns_resolver" "$api_upstream" > /tmp/api-upstream.conf
exec nginx -g 'daemon off;'
