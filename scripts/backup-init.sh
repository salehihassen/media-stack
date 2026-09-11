#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$project_dir/backup/restic.env"
password_file="$project_dir/backup/restic-password"

[ -r "$env_file" ] || { echo "Missing $env_file; copy backup/restic.env.example first." >&2; exit 1; }
[ -r "$password_file" ] || { echo "Missing $password_file; create the Restic repository password first." >&2; exit 1; }

exec docker run --rm \
  --env-file "$env_file" \
  -v "$password_file:/run/secrets/restic-password:ro" \
  restic/restic:0.19.1 init
