#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
rendered_config=$(mktemp)
trap 'rm -f "$rendered_config"' EXIT HUP INT TERM

cd "$project_dir"

# Validation renders the stack but never starts it. This placeholder satisfies
# Gluetun's required Compose interpolation without exposing a real VPN setting.
: "${VPN_SERVICE_PROVIDER:=ci}"
export VPN_SERVICE_PROVIDER

docker compose config --quiet
docker compose --profile rip config --quiet
docker compose --profile rip config --format json > "$rendered_config"

assert_json() {
  description=$1
  filter=$2

  if ! jq -e "$filter" "$rendered_config" >/dev/null; then
    printf 'FAILED: %s\n' "$description" >&2
    exit 1
  fi
}

assert_json 'qBittorrent must share Gluetun network namespace' \
  '.services.qbittorrent.network_mode == "service:gluetun"'
assert_json 'FlareSolverr must not publish a host port' \
  '((.services.flaresolverr.ports // []) | length) == 0'
assert_json 'only Jellyfin may publish beyond localhost' \
  '([.services | to_entries[] | select(.key != "jellyfin") | .value.ports[]? | select(.host_ip != "127.0.0.1")] | length) == 0'
assert_json 'Jellyfin must publish only its HTTP port to the LAN' \
  '(.services.jellyfin.ports | length) == 1 and .services.jellyfin.ports[0].host_ip == "0.0.0.0" and .services.jellyfin.ports[0].target == 8096'
assert_json 'MakeMKV and HandBrake must remain opt-in rip services' \
  '.services.makemkv.profiles == ["rip"] and .services.handbrake.profiles == ["rip"]'
assert_json 'MakeMKV host devices must use adapter staging paths' \
  '([.services.makemkv.devices[] | select(.target == "/dev/media-extract-sr")] | length) == 1 and ([.services.makemkv.devices[] | select(.target == "/dev/media-extract-sg")] | length) == 1'
assert_json 'MakeMKV device adapter must hand off to the image init' \
  '.services.makemkv.command == ["/init"]'
assert_json 'Sonarr must read torrent payloads without write access' \
  '([.services.sonarr.volumes[]? | select(.target == "/data/torrent" and .read_only == true)] | length) == 1'
assert_json 'Radarr must read torrent payloads without write access' \
  '([.services.radarr.volumes[]? | select(.target == "/data/torrent" and .read_only == true)] | length) == 1'
assert_json 'Jellyfin must read the media library without write access' \
  '([.services.jellyfin.volumes[]? | select(.target == "/data/media" and .read_only == true)] | length) == 1'
assert_json 'HandBrake must read MakeMKV output without write access' \
  '([.services.handbrake.volumes[]? | select(.target == "/storage" and .read_only == true)] | length) == 1'

find scripts -type f -name '*.sh' -exec sh -n {} \;

for ignored_path in .env config/private data/private backup/restic.env backup/restic-password; do
  if ! git check-ignore -q -- "$ignored_path"; then
    printf 'FAILED: %s must be ignored by Git\n' "$ignored_path" >&2
    exit 1
  fi
done

printf '%s\n' 'Stack configuration and safety-boundary validation passed.'
