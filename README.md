# Media Stack

A portable personal-media stack containing Jellyfin, Radarr, Sonarr, Prowlarr,
qBittorrent behind a Gluetun VPN kill switch, plus optional MakeMKV and
HandBrake web UIs for disc ripping and transcoding.
Use torrents and disc copying only where you have the legal right to do so.

## Attribution

I used Codex CLI to generate this stack. Due to similarities I believe this other stack may have inspired this one.

https://github.com/bryce-hoehn/automated-jellyfin-guide

## Layout

```text
media-extract/
├── compose.yaml                  # stack definition (tracked in Git)
├── .env                          # host settings and VPN credentials (never commit)
├── config/<service>/             # application settings/databases (never commit)
└── data/                         # runtime data (never commit)
    ├── torrent/{incomplete,complete}/
    ├── media/{movies,tv}/
    ├── jellyfin/cache/
    ├── makemkv/{storage,output}/
    └── handbrake/output/
```

qBittorrent, Sonarr, and Radarr all use the same in-container download path,
`/data/torrent/...`, which avoids fragile Remote Path Mappings. Their access is
otherwise deliberately restricted: qBittorrent can write only to the torrent
tree; Radarr can write only to the Movies library; Sonarr can write only to the
Shows library; and Jellyfin reads media without write access.

The resulting import flow is `qBittorrent → data/torrent/complete → Radarr or
Sonarr → data/media/{movies,tv} → Jellyfin`. Jellyfin is independent of the
*arr applications: it does not search, download, or receive an import event
from them; it discovers imported files by scanning its library folders.

## First start and manual application setup (required)

1. Copy `.env.example` to `.env`, set `PUID`/`PGID` (`id -u` and `id -g`),
   and enter the credentials required by your VPN provider. Provider-specific
   Gluetun variables are documented at
   <https://github.com/qdm12/gluetun-wiki/tree/main/setup/providers>.
   For ProtonVPN OpenVPN, use the separate OpenVPN/IKEv2 username and password
   from <https://account.proton.me/u/0/vpn/OpenVpn>, rather than the password
   used to sign in to Proton's website.
2. Create and own the directories:

   ```sh
   mkdir -p config/{gluetun,qbittorrent,prowlarr,sonarr,radarr,jellyfin,makemkv} \
     data/{torrent/{incomplete,complete},media/{movies,tv},jellyfin/cache,makemkv/{storage,output},handbrake/output}
   sudo chown -R "$(id -u):$(id -g)" config data
   ```

3. Validate and launch:

   ```sh
   ./scripts/preflight.sh
   docker compose config --quiet
   docker compose up -d
   docker compose ps
   docker compose logs gluetun qbittorrent
   ```

Do not continue until Gluetun reports a healthy VPN connection. qBittorrent
shares Gluetun's network namespace, so it has no independent route if the VPN
goes down. Its web UI is exposed through Gluetun at <http://localhost:8080>.
LinuxServer prints qBittorrent's temporary first-run password in its logs.

The administrative interfaces (qBittorrent, Prowlarr, Sonarr, Radarr, and
MakeMKV) bind only to `127.0.0.1`. Jellyfin alone binds to `0.0.0.0` on port
`8096`, making it available to devices on the local network.

Docker starts the services, but it cannot safely configure application accounts,
VPN credentials, download-client credentials, or third-party sources for you.
After the launch steps above complete successfully, continue with the following
one-time configuration.

### 1. Reach the interfaces

Jellyfin is available to the local network at `http://<c3-address>:8096`.
All other interfaces bind only to C3's localhost. Access them directly from C3
or create an SSH tunnel from an administrator workstation:

```sh
ssh -N -o ExitOnForwardFailure=yes \
  -L 8080:127.0.0.1:8080 \
  -L 7878:127.0.0.1:7878 \
  -L 8989:127.0.0.1:8989 \
  -L 9696:127.0.0.1:9696 \
  -L 5800:127.0.0.1:5800 \
  -L 5801:127.0.0.1:5801 \
  c3
```

After tunnelling, use `http://localhost:<port>` for qBittorrent (`8080`),
Radarr (`7878`), Sonarr (`8989`), Prowlarr (`9696`), MakeMKV (`5800`), and
HandBrake (`5801`).

### 2. Secure and configure qBittorrent

On first launch, LinuxServer prints a temporary qBittorrent password in
`docker compose logs qbittorrent`. Sign in as `admin`, then go to **Settings →
Web UI** and set a permanent username and password. This is required: if the
password is not changed, qBittorrent generates a different temporary password
on every restart. The permanent password is stored as a hash in the persistent
`config/qbittorrent` volume, which is excluded from Git and included in the
optional encrypted configuration backup.

In **Settings → Downloads**, verify:

- Default save path: `/data/torrent/complete`
- Keep incomplete torrents in: `/data/torrent/incomplete`

In **Settings → BitTorrent → Seeding Limits** (called **Share Ratio Limiting**
in some qBittorrent versions), enable **When ratio reaches**, set it to `0`,
and select **Stop torrent**. The persistent qBittorrent configuration currently
uses this same `ratio 0 → Stop` setting; verify it after a qBittorrent upgrade
or configuration reset. This stops a torrent after it finishes; it cannot
prevent uploads that occur while it is still downloading.

Because Sonarr and Radarr have read-only access to completed torrents, set
**Use Hardlinks instead of Copy** to off in each application's **Settings →
Media Management**. Imports will copy the completed file into the relevant
library and cannot remove or alter torrent source files.

### 3. Connect Sonarr and Radarr to qBittorrent

In **Sonarr → Settings → Download Clients**, add qBittorrent with:

- Host: `gluetun`
- Port: `8080`
- Authentication: qBittorrent API key (preferred for this stack)
- Category: `tv`

In **Sonarr → Settings → Media Management**, add root folder
`/data/media/tv`. Copy Sonarr's API key from **Settings → General**.

In **Radarr → Settings → Download Clients**, add qBittorrent with the same
host, port, and qBittorrent API key, but set category to `movies`. In **Media
Management**, add root folder `/data/media/movies`. Copy Radarr's API key from
**Settings → General**.

Generate or copy the qBittorrent API key from qBittorrent's Web UI, then enter
it in the qBittorrent authentication/API-key field in both Sonarr and Radarr.
Do not commit this key: it is application configuration stored in the ignored
service config volume. The Sonarr/Radarr API keys copied above are separate and
are used later by Prowlarr when connecting *to* Sonarr and Radarr.

`gluetun:8080` is deliberate: qBittorrent shares Gluetun's network namespace,
so other containers reach its Web UI through the Gluetun hostname. qBittorrent
alone performs torrent transfers, and its traffic stays behind ProtonVPN.

### 4. Connect Prowlarr to Sonarr and Radarr

In **Prowlarr → Settings → Apps**, add:

- Sonarr URL: `http://sonarr:8989`, using the Sonarr API key
- Radarr URL: `http://radarr:7878`, using the Radarr API key

Test and save each application. Add only sources/indexers that you are
authorized to access and whose terms allow this use. Prowlarr supplies search
results to Sonarr/Radarr; it does not download media. There is intentionally no
source or indexer configuration embedded in this repository.

### 5. Configure Jellyfin libraries

Create two Jellyfin libraries:

- **Movies**: `/data/media/movies`
- **Shows**: `/data/media/tv`

Jellyfin does not search Prowlarr or fetch downloads. It reads the files that
Radarr and Sonarr have imported into these folders. These are *container*
paths, so do not enter host-relative paths such as `data/media/movies` in the
Jellyfin UI.

If an imported movie or episode is missing, first confirm the appropriate
Jellyfin library contains the exact folder above and has the matching content
type (**Movies** or **Shows**). Then open **Dashboard → Scheduled Tasks** and
run **Scan Media Library** (or use the library's **Scan Library** action).
Refreshing metadata only updates items already known to Jellyfin; it does not
reliably discover a newly imported file.

Change these folders only from **Dashboard → Libraries → Manage Libraries**.
The **Edit** dialog opened from an individual movie edits that item's metadata;
its displayed path is not how a library folder is changed. A fresh Jellyfin
onboarding can create a default `Movies` library at
`/config/data/root/default/Movies`; replace that library folder with
`/data/media/movies` (or remove the default library and create the Movies
library again), then run a media-library scan.

### 6. Configure FlareSolverr for an authorized protected source

FlareSolverr is internal-only: it has no host-published port. Start or update
the stack normally with `docker compose up -d`, then in Prowlarr go to
**Settings → Indexers → Indexer Proxies → Add** and select **FlareSolverr**.
Set its URL to `http://flaresolverr:8191`, give it a unique tag such as
`flaresolverr`, and test/save it. Add that same tag only to the authorized
indexer that needs it. Do not apply it globally; Prowlarr uses this proxy only
when both the proxy and indexer have the same tag.

FlareSolverr and Prowlarr use the host's normal outbound connection in this
design. qBittorrent remains exclusively behind Gluetun and ProtonVPN. This
keeps torrent traffic protected by the VPN without routing the management
applications through it. A protected source may still reject automated access
or require a human CAPTCHA; do not attempt to bypass any access control beyond
what its terms explicitly permit.

## Verify the VPN kill switch

Compare the host and downloader public IPs:

```sh
curl -s https://ipinfo.io/ip
docker compose exec qbittorrent curl -s https://ipinfo.io/ip
```

They should differ. Then stop Gluetun and confirm qBittorrent stops with it:

```sh
docker compose stop gluetun
docker compose ps
docker compose up -d gluetun qbittorrent
```

## Optional disc ripping and transcoding

MakeMKV and HandBrake share the opt-in `rip` profile, so neither a missing
optical device nor a transcoding workload prevents the torrent-only stack from
starting. Once the profile has been started, Docker restarts these containers
after a host reboot unless they were explicitly stopped.

On a native Linux Docker host, attach the reader, run
`./scripts/find-optical-drive.sh`, then set the reported `DVD_DEVICE` and
`DVD_SG_DEVICE` in `.env`. For example, a single reader often appears as
`/dev/sr0` and `/dev/sg0`. Start the profile:

```sh
docker compose --profile rip up -d
```

Open MakeMKV at <http://localhost:5800> and rip into `/output`. That is the
host's `data/makemkv/output/` staging directory; it is intentionally not a
Jellyfin library. MakeMKV has no write access to `data/media`.

### Automatic ripping and disc ejection

The current MakeMKV service enables its built-in automatic disc ripper. After
the container is fully running, insert a DVD or Blu-ray and MakeMKV detects,
rips, and ejects it after successful completion. A unique directory beneath
`data/makemkv/output/` is used for every disc, even when two discs share a
label.

The automatic ripper deliberately ignores a disc that is already inserted when
the container starts or is recreated. This prevents an unexpected rip after a
service restart. If the log says **Service first run**, eject and reinsert that
disc; do not start the rip through the web UI if testing automatic mode.

Automatic ejection applies only to automatic-ripper jobs. A rip started in the
MakeMKV web UI completes normally but does not use the automatic-ripper eject
step. To observe an automatic job, run:

```sh
docker compose logs -f makemkv
```

Wait for a rip to complete and the disc to eject before applying Compose or
image updates. Any `docker compose up -d` that changes the MakeMKV definition,
`docker compose down`, host reboot, Docker-daemon restart, or device disconnect
can interrupt an active rip. `restart: unless-stopped` restores the container
after a reboot; it does not preserve an interrupted optical read.

MakeMKV supports completion hooks in `config/makemkv/hooks/`. In particular,
`disc_rip_terminated.sh` is invoked for automatic jobs with the drive ID, disc
label, output directory, and final `SUCCESS` or `FAILURE` status. It can later
send a Home Assistant, Loki, ntfy, email, or other notification. GUI-initiated
rips use the separate `gui_disc_rip_terminated.sh` hook.

Open HandBrake at <http://localhost:5801>. Its `/storage` folder is the
MakeMKV output mounted read-only; write its encoded result to `/output`, which
is the separate host directory `data/handbrake/output/`. HandBrake cannot alter
a raw rip, a torrent payload, or the Jellyfin library.

HandBrake is currently a manual, optional stage. Automatic transcoding after a
MakeMKV rip is intentionally **not** enabled yet: first confirm that automatic
ripping, output naming, ejection, and Manual Import behave correctly for both
DVD and Blu-ray discs. When this workflow has been validated, an explicit
completion-hook-driven transcode design can be added without granting HandBrake
write access to the raw-rip, torrent, or Jellyfin-library directories.

To publish either a raw MakeMKV rip or a HandBrake encode, use **Wanted →
Manual Import** in the appropriate *arr application. Sonarr can read
`/data/import/makemkv` and `/data/import/handbrake` and writes only to its TV
library; Radarr has the same sources and writes only to its Movies library.
After verifying the import, delete unwanted staging files from the host.
MakeMKV licensing/activation is separate from this stack. HandBrake transcodes
the files MakeMKV has already made readable; it does not itself handle protected
discs.

Docker Desktop's Linux VM on Windows 11 does not generally expose a host USB
optical drive as `/dev/sr*` and `/dev/sg*`. The dependable Windows options are
the native MakeMKV application, or running this Compose stack in a Linux VM
with USB passthrough. A Linux server/NAS host is the simplest portable setup.

## Updating and backups

```sh
docker compose pull
docker compose up -d
```

Back up `.env` and `config/`. The `data/` tree can be backed up independently.
Images use rolling stable tags for convenience; for repeatable deployments,
replace them with tested immutable version tags or digests after the first
successful setup.

## Version control and encrypted configuration backup

This directory is intended to be a Git repository. Commit Compose, scripts,
documentation, and examples. `.env`, generated service configuration (including
the qBittorrent password hash), all data, and B2 credentials are excluded from
Git.

`backup/` contains a Restic-to-Backblaze-B2 job. It backs up configuration and
application secrets (including `.env`) encrypted, while excluding `data/` and
the B2 bootstrap credentials. See [backup/README.md](backup/README.md) for its
one-time setup and systemd timer installation.

For future coding-agent sessions, see [CODEX_HANDOFF.md](CODEX_HANDOFF.md).
