# Media Extract: Coding-Agent Handoff

This is a private, portable Docker Compose stack at
`/home/saleh/apps/media-extract` on host `c3`. Treat the current checkout and
runtime configuration as user-owned. Do not reveal, read into chat, commit, or
replace `.env`, `config/`, `data/`, `backup/restic.env`, or
`backup/restic-password`.

## Current design

- Jellyfin is the playback server only. It is published on `0.0.0.0:8096`.
- qBittorrent shares Gluetun's network namespace and is the only torrent
  client. Its Web UI is published by Gluetun on `127.0.0.1:8080`; transfers use
  Gluetun/ProtonVPN.
- Prowlarr (`9696`), Sonarr (`8989`), Radarr (`7878`), optional MakeMKV
  (`5800`), and optional HandBrake (`5801`) are localhost-only. FlareSolverr
  is internal-only at `http://flaresolverr:8191`.
- The Compose network is named `media-extract`. Containers use service DNS;
  qBittorrent must be addressed by the other containers as `gluetun:8080`, not
  `qbittorrent:8080`.
- Only authorized sources are in scope. No source-specific configuration is
  stored in this repository.

## Filesystem contract

All containers use these *in-container* paths:

| Service | Read/write paths | Read-only paths |
| --- | --- | --- |
| qBittorrent | `/data/torrent` | none |
| Radarr | `/data/media/movies` | `/data/torrent`, `/data/import/makemkv`, `/data/import/handbrake` |
| Sonarr | `/data/media/tv` | `/data/torrent`, `/data/import/makemkv`, `/data/import/handbrake` |
| Jellyfin | none | `/data/media` |
| MakeMKV | `/config`, `/storage`, `/output` | none |
| HandBrake | `/config`, `/output` | `/storage` |

Host equivalents are under `data/`. qBittorrent saves completed work to
`/data/torrent/complete` and temporary work to `/data/torrent/incomplete`.
Radarr/Sonarr must use `/data/media/movies` and `/data/media/tv` respectively.
Because their torrent mount is read-only, hardlink imports must remain disabled;
they copy media into the libraries.

MakeMKV's `/output` is host `data/makemkv/output`: raw disc-rip staging, never
a Jellyfin library. HandBrake reads that location as `/storage` and writes
candidate encodes to host `data/handbrake/output` at `/output`. Neither
container has access to torrent payloads or write access to `data/media`.
Use the relevant *arr application's **Wanted → Manual Import** from its
read-only `/data/import/makemkv` or `/data/import/handbrake` source to publish
a selected result into the canonical library.

Do not use Radarr/Sonarr Remote Path Mappings. A prior mismatch had
qBittorrent report `/data/downloads/...` while Radarr saw the host directory at
`/data/torrent/...`, which caused import failures. The shared `/data/torrent`
contract above is the fix. Pre-existing qBittorrent jobs that still reference
`/data/downloads` may need manual cleanup; do not change the new mapping to
accommodate them.

## Manual application facts

- The user prefers a qBittorrent API key in Sonarr/Radarr rather than stored
  qBittorrent username/password credentials. Preserve that preference unless
  the user asks otherwise.
- qBittorrent's desired no-seed policy is **ratio 0, Stop torrent**. It will
  still participate in the swarm while downloading.
- Jellyfin library roots must be `/data/media/movies` (Movies) and
  `/data/media/tv` (Shows). A metadata refresh does not discover a new file;
  use **Dashboard → Scheduled Tasks → Scan Media Library** or **Scan Library**.
- Change Jellyfin folders through **Dashboard → Libraries → Manage Libraries**,
  never through an individual item's metadata **Edit** dialog. Jellyfin's
  onboarding default `/config/data/root/default/Movies` is a config-volume
  folder, not this stack's movie library; replace it with `/data/media/movies`.
- Jellyfin does not integrate directly with Prowlarr/Radarr/Sonarr. It scans
  the completed media tree after an import.
- FlareSolverr is deliberately outside Gluetun and uses normal host egress.
  qBittorrent remains VPN-routed. Do not route FlareSolverr through Gluetun
  without an explicit user request; using a separate VPN gateway would be the
  safer future design if requested.

## Operations

- Run `./scripts/preflight.sh` before an initial start or port change; it checks
  the host's TCP listeners against every published Compose port.
- Run `docker compose config --quiet` before applying Compose edits and
  `docker compose ps` afterward. Avoid blanket rebuilds/recreates when only one
  service needs attention.
- The running qBittorrent configuration contains a password hash and is ignored
  by Git. Never add `config/qbittorrent/qBittorrent/qBittorrent.conf` to Git.
- B2/Restic configuration backup is implemented but has not necessarily been
  initialized or scheduled. It intentionally excludes all of `data/`, including
  media, torrents, caches, and MakeMKV output. It includes `.env` and `config/`
  encrypted in B2. The Restic password and B2 bootstrap credentials are not
  themselves backed up.
- MakeMKV uses the optional `rip` Compose profile and physical `/dev/sr*` and
  `/dev/sg*` devices. It should not be started by default on hosts without the
  optical drive. On this host the known matching pair is `/dev/sr0` and
  `/dev/sg0`; use `./scripts/find-optical-drive.sh` on another host.
- The `rip` profile starts MakeMKV and HandBrake. Both use `restart:
  unless-stopped`, so Docker restarts them after a host reboot once they have
  been created. Do not change their Compose definition, run `docker compose
  down`, or apply image/configuration updates while an optical rip is active:
  Compose can recreate MakeMKV and interrupt the read.
- MakeMKV automatic ripping is deliberately enabled with automatic eject and
  unique output directories. It ignores a disc already present when the
  container starts or is recreated; eject and reinsert it. Automatic eject
  applies only to automatic-ripper jobs, not a rip started through the GUI.
- MakeMKV hooks are under the ignored, persistent
  `config/makemkv/hooks/` directory. `disc_rip_terminated.sh` receives drive
  ID, disc label, output directory, and `SUCCESS`/`FAILURE` for automatic
  jobs; GUI jobs use `gui_disc_rip_terminated.sh`. Hooks may later notify Home
  Assistant, Loki, or another external system.
- HandBrake is intentionally manual for now. Do not implement automatic
  post-rip transcoding until the user has validated automatic ripping, ejection,
  output naming, and Manual Import for both DVD and Blu-ray media. Any future
  automation must preserve the current least-privilege contract: no HandBrake
  write access to raw rips, torrents, or the Jellyfin library.
