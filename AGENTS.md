# Guardrails

- Inspect diffs and runtime first. Preserve uncommitted work; never expose or commit secrets or runtime data.
- Never interrupt an active rip. Recreate only the affected service; validate changes with `./scripts/ci-validate.sh`.
- Preserve VPN routing, localhost-only admin ports, and read-only mounts. Use shared `/data/torrent` paths, not Remote Path Mappings.
- Raw rips are staging, not library media. Import through Sonarr/Radarr; keep HandBrake manual.
- Preserve stable optical aliases, long-form Compose devices, adapter `/init` handoff, and actual device supplementary groups. Verify access as the app user, not just root.
- Never probe optical media with `blkid` or bare `udevadm test`; use README's isolated simulation. Verify the early probe-disable rule before requesting physical retries; stop repeated retries if the drive wedges.
