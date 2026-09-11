#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_file=$(mktemp)
trap 'rm -f "$config_file"' EXIT HUP INT TERM

# A real .env takes precedence. This placeholder permits validation before the
# user has created one; it is never used to start the stack.
: "${VPN_SERVICE_PROVIDER:=preflight}"
export VPN_SERVICE_PROVIDER

(cd "$project_dir" && docker compose --profile rip config --format json) > "$config_file"

ports=$(jq -r '.services | to_entries[] | .value.ports[]? | .published // empty' "$config_file" | sort -nu)
status=0
for port in $ports; do
  if ss -ltnH "sport = :$port" | grep -q .; then
    printf 'CONFLICT: TCP port %s is already listening:\n' "$port" >&2
    ss -ltnp "sport = :$port" >&2 || true
    status=1
  else
    printf 'available: TCP port %s\n' "$port"
  fi
done

exit "$status"
