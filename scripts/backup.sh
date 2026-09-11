#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
env_file="$project_dir/backup/restic.env"
password_file="$project_dir/backup/restic-password"

[ -r "$env_file" ] || { echo "Missing $env_file; copy backup/restic.env.example first." >&2; exit 1; }
[ -r "$password_file" ] || { echo "Missing $password_file; create the Restic repository password first." >&2; exit 1; }

common_args="--exclude=/source/data --exclude=/source/.git --exclude=/source/.firecrawl --exclude=/source/backup/restic.env --exclude=/source/backup/restic-password --exclude=/source/backup/logs"

# shellcheck disable=SC2086
docker run --rm \
  --env-file "$env_file" \
  -v "$project_dir:/source:ro" \
  -v "$password_file:/run/secrets/restic-password:ro" \
  restic/restic:0.19.1 backup $common_args /source

docker run --rm \
  --env-file "$env_file" \
  -v "$password_file:/run/secrets/restic-password:ro" \
  restic/restic:0.19.1 forget --prune \
    --keep-daily 14 --keep-weekly 8 --keep-monthly 24
