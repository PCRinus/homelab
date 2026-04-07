# Media Server Stack

This directory contains the Docker Compose configuration for the media server stack.

## Services

| Service | Port | Description |
|---------|------|-------------|
| qBittorrent | 8080 | Torrent client with built-in WireGuard VPN (Hotio image) |
| Sonarr | 8989 | TV series management |
| Radarr | 7878 | Movie management |
| Prowlarr | 9696 | Indexer manager |
| Bazarr | 6767 | Subtitle management |
| Seerr | 5055 | Media request system |
| Pulsarr | 3003 | Plex watchlist automation and routing |
| Plex | 32400 | Media server |
| FlareSolverr | 8191 | Cloudflare bypass for indexers |
| Configarr | - | Quality profiles & custom formats via TRaSH-Guides |

### NAS Mount (NFS)

The media stack requires `/mnt/unas/media` to be mounted from the NAS before starting services.

**fstab entry** (`/etc/fstab`):
```
192.168.1.30:/var/nfs/shared/Media  /mnt/unas/media  nfs  defaults,_netdev,x-systemd.automount,x-systemd.mount-timeout=30,rw,hard  0  0
```

The `x-systemd.automount` option creates an automount unit that mounts the NFS share on first access, avoiding race conditions with network initialization at boot time.

**Manual mount** (if needed after reboot):
```bash
sudo mount -a
# Or specifically:
sudo mount /mnt/unas/media
```

**Verify mount**:
```bash
df -h | grep unas
# Should show: 192.168.1.30:/var/nfs/shared/Media mounted at /mnt/unas/media
```

### Host Setup (Rootful Docker)

For reliable GPU access in Plex hardware transcoding, keep render device permissions configured on the host.

**Udev rule** (already applied at `/etc/udev/rules.d/99-render-device.rules`):
```
SUBSYSTEM=="drm", KERNEL=="renderD*", MODE="0666"
```

If setting up from scratch:
```bash
# Create udev rule for render device permissions
echo 'SUBSYSTEM=="drm", KERNEL=="renderD*", MODE="0666"' | sudo tee /etc/udev/rules.d/99-render-device.rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Add user to render group (for non-Docker access)
sudo usermod -aG render $USER
```

### Compose Configuration

The Plex service passes through the GPU:
```yaml
devices:
  - /dev/dri:/dev/dri  # AMD Vega GPU for VA-API
device_cgroup_rules:
  - 'c 226:* rwm'      # Allow access to DRI devices
group_add:
  - "993"             # render group GID
```

### Verify It's Working

```bash
# Monitor GPU usage during transcoding
watch -n 1 cat /sys/class/drm/card0/device/gpu_busy_percent
```

## Tautulli: Plex Log Viewer Setup

Tautulli can read Plex log files directly, but only if the Plex logs directory is mounted into the Tautulli container.

### 1) Mount Plex logs into Tautulli

In `compose.yml`, the `tautulli` service should include this read-only bind mount:

```yaml
tautulli:
  volumes:
    - ${DOCKER_DATA}/tautulli:/config
    - type: bind
      source: "${DOCKER_DATA}/plex/config/Library/Application Support/Plex Media Server/Logs"
      target: /plex-logs
      read_only: true
```

Apply changes:

```bash
cd /home/mircea/homeserver/media-server
docker compose up -d tautulli
```

### 2) Configure Tautulli log folder

In Tautulli UI:

1. Go to **Settings → Logs**
2. Set **Plex Logs Folder** to:

   ```
   /plex-logs
   ```

3. Save and refresh the Logs page

### 3) Verify

- Open **Logs → Plex Media Server Logs**
- Select `Plex Media Server.log` from the dropdown
- Set a refresh rate to watch entries in near real time

If you set `/config/logs`, Tautulli will only read its own logs and Plex logs will appear empty.

## VPN Setup (Hotio qBittorrent + ProtonVPN)

The Hotio qBittorrent image includes built-in WireGuard VPN support with automatic port forwarding for ProtonVPN.

### How It Works

- **qBittorrent (Hotio)** has WireGuard built-in - no separate VPN container needed
- **`VPN_AUTO_PORT_FORWARD=true`** automatically retrieves and configures the forwarded port
- **`VPN_HEALTHCHECK_ENABLED=true`** marks container unhealthy if VPN fails

### Configuration

WireGuard config file location: `/home/mircea/docker/qbittorrent/wireguard/wg0.conf`

To set up:
1. Go to https://account.protonvpn.com/downloads
2. Select: WireGuard configuration, Platform: Router
3. Enable: NAT-PMP (Port Forwarding)
4. Choose a Netherlands P2P server
5. Save the config to `/home/mircea/docker/qbittorrent/wireguard/wg0.conf`

### Checking VPN Status

```bash
# Check if VPN is connected (should show VPN IP, not home IP)
docker exec qbittorrent curl -s ifconfig.me

# View qBittorrent/VPN logs
docker logs qbittorrent
```

### Port Forwarding for Seeding

Port forwarding is **automatic** with `VPN_AUTO_PORT_FORWARD=true`. The Hotio image retrieves the forwarded port from ProtonVPN and configures qBittorrent automatically.

## Torrent Client Setup (qBittorrent)

### Configuration

qBittorrent stores its configuration in `/home/mircea/docker/qbittorrent/`. Settings are managed via the WebUI.

**Key settings:**
- Download directory: `/data/torrents`
- Incomplete directory: `/data/torrents/incomplete`
- WebUI port: 8080
- Peer port: (automatically configured by VPN_AUTO_PORT_FORWARD)

### Starting the Stack

```bash
cd /home/mircea/homeserver/media-server
./start.sh
```

### Authentication

The Hotio image does **not** support environment variables for WebUI credentials (unlike linuxserver). On first launch, qBittorrent generates a temporary password:

```bash
docker logs qbittorrent | grep -i password
```

Log in with the temporary password and set your permanent credentials via **Tools → Options → Web UI**.

The `.env` variables `QBITTORRENT_USER` and `QBITTORRENT_PASS` are still used by Homepage widgets to authenticate with qBittorrent's API.

### Hotio Image Directory Structure

The Hotio qBittorrent image uses a different directory layout than linuxserver:

```
/home/mircea/docker/qbittorrent/     # Mounted as /config in container
├── config/                          # qBittorrent app config
│   ├── qBittorrent.conf             # Main config file
│   └── categories.json              # Download categories
├── data/                            # qBittorrent data
│   └── BT_backup/                   # Torrent resume data (*.torrent + *.fastresume)
└── wireguard/
    └── wg0.conf                     # WireGuard VPN config
```

**Important:** If migrating from linuxserver, torrent resume data must be copied to `/config/data/BT_backup/` (not `/config/qBittorrent/BT_backup/`).

### Download Client Configuration in Sonarr/Radarr

| Setting | Value |
|---------|-------|
| Host | `qbittorrent` |
| Port | `8080` |
| Username | (from .env) |
| Password | (from .env) |
| Category | `tv-sonarr` / `radarr` |

## Media Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐
│  Pulsarr    │────▶│ Sonarr/     │────▶│    qBittorrent      │
│ (watchlist) │     │ Radarr      │     │    (download)       │
└─────────────┘     └─────────────┘     └──────────┬──────────┘
                                                   │
                           ┌───────────────────────┘
                           ▼
              ┌────────────────────────┐
              │  /data/torrents/       │
              │  ├── incomplete/       │  ◀── Active downloads
              │  ├── movies/           │  ◀── Completed (seeding)
              │  └── tv/               │  ◀── Completed (seeding)
              └────────────┬───────────┘
                           │
                           │ Sonarr/Radarr import
                           │ (hardlink or copy)
                           ▼
              ┌────────────────────────┐
              │  /data/media/          │
              │  ├── movies/           │  ◀── Plex library
              │  └── tv/               │  ◀── Plex library
              └────────────┬───────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │    Plex     │
                    │  (stream)   │
                    └─────────────┘
```

### Directory Structure

```
/mnt/unas/media/                 # NAS mount (mapped to /data in containers)
├── incomplete/                  # Active downloads (qBittorrent temp dir)
│   ├── radarr/                  # Active movie downloads
│   ├── tv-sonarr/               # Active TV downloads
│   └── anime-sonarr/            # Active anime downloads
├── torrents/                    # Completed downloads (seeding)
│   ├── movies/                  # Completed movie torrents
│   ├── tv/                      # Completed TV torrents
│   └── anime/                   # Completed anime torrents
└── media/                       # Media libraries (Plex)
    ├── movies/                  # Movie library
    ├── tv/                      # TV library
    └── anime/                   # Anime library
```

### How Downloads Are Organized

qBittorrent uses **categories** to organize downloads. Configure categories in Sonarr/Radarr:

| App | Category | Save Path |
|-----|----------|-----------|
| Sonarr | `tv-sonarr` | `/data/torrents/tv` |
| Sonarr Anime | `anime-sonarr` | `/data/torrents/anime` |
| Radarr | `radarr` | `/data/torrents/movies` |

### Hardlinks

Since `/data/torrents` and `/data/media` are on the same filesystem (NAS), Sonarr/Radarr use **hardlinks** when importing. This means:
- Instant "moves" (no copying)
- Files exist in both locations but use disk space only once
- qBittorrent keeps seeding from `torrents/` while Plex serves from `media/`

## API Commands

Useful API commands for managing the *arr stack. Source the `.env` file first to get API keys:

```bash
source /home/mircea/homeserver/.env
```

### Radarr

**Search for all missing movies:**
```bash
curl -s "http://localhost:7878/api/v3/command" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "MissingMoviesSearch"}'
```

**Refresh all movies (rescan disk):**
```bash
curl -s "http://localhost:7878/api/v3/command" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "RefreshMovie"}'
```

**List queue (active downloads):**
```bash
curl -s "http://localhost:7878/api/v3/queue" \
  -H "X-Api-Key: $RADARR_API_KEY" | jq '.records[] | {title: .title, status: .status}'
```

**Search for upgrades (cutoff unmet):**
```bash
curl -s "http://localhost:7878/api/v3/command" \
  -H "X-Api-Key: $RADARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "CutoffUnmetMoviesSearch"}'
```

### Sonarr

**Search for all missing episodes:**
```bash
curl -s "http://localhost:8989/api/v3/command" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "MissingEpisodeSearch"}'
```

**Refresh all series (rescan disk):**
```bash
curl -s "http://localhost:8989/api/v3/command" \
  -H "X-Api-Key: $SONARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "RefreshSeries"}'
```

**List queue (active downloads):**
```bash
curl -s "http://localhost:8989/api/v3/queue" \
  -H "X-Api-Key: $SONARR_API_KEY" | jq '.records[] | {title: .title, status: .status}'
```

### Prowlarr

**Test all indexers:**
```bash
curl -s "http://localhost:9696/api/v1/command" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "TestAllIndexers"}'
```

**Sync indexers to apps:**
```bash
curl -s "http://localhost:9696/api/v1/command" \
  -H "X-Api-Key: $PROWLARR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "SyncIndexers"}'
```

## Bazarr + Plex Integration

Bazarr connects to Plex to trigger library refreshes after downloading subtitles. When authenticating via OAuth, Bazarr auto-selects a Plex connection URL, but it often picks the `.plex.direct` secure URL which doesn't work well from within the Docker network.

### Initial Setup

1. **Connect to Plex via OAuth** in Bazarr Settings → Plex
2. **Fix the server URL** (see below) - required before libraries can be detected
3. **Select Plex libraries** to monitor (e.g., "Movies", "TV Shows") in Settings → Plex

### Fix: Use Internal Docker Hostname

After connecting Bazarr to Plex via OAuth, manually update the server URL in the config:

```bash
# Stop Bazarr
cd /home/mircea/homeserver/media-server && docker compose stop bazarr

# Edit config
docker run --rm -v /home/mircea/docker/bazarr/config:/config alpine \
  sed -i 's|server_url: https://.*plex.direct:32400|server_url: http://plex:32400|' /config/config.yaml

# Verify the change
grep "server_url" /home/mircea/docker/bazarr/config/config.yaml
# Should show: server_url: http://plex:32400

# Start Bazarr
docker compose start bazarr
```

This changes the connection from `https://*.plex.direct:32400` (external, can timeout) to `http://plex:32400` (internal Docker network, fast and reliable).

## Configarr (Quality Profiles & Custom Formats)

Configarr syncs quality profiles and custom formats from [TRaSH-Guides](https://trash-guides.info/) to Sonarr and Radarr. This enables 4K content, HDR preferences, and optimized release scoring.

### What It Does

- **Quality Profiles**: Pre-configured profiles like `WEB-1080p`, `WEB-2160p` (4K), `HD Bluray + WEB`, `UHD Bluray + WEB`
- **Custom Formats**: Scoring rules for HDR, Dolby Vision, audio codecs, release groups, etc.
- **Automatic Sync**: Pulls latest recommendations from TRaSH-Guides

### Configuration

- Config: `configarr/config.yml` - Defines which profiles/formats to sync
- Secrets: `configarr/secrets.yml` - API keys (gitignored, see `.example`)

### Usage

Configarr is a **one-shot job**, not a daemon. Run it manually or via cron:

```bash
# Run once to sync profiles
cd /home/mircea/homeserver/media-server
docker compose run --rm configarr

# Dry-run to see what would change (check logs)
docker compose run --rm configarr
```

### Setting Up Secrets

```bash
# Copy example and fill in API keys
cp configarr/secrets.yml.example configarr/secrets.yml

# Get API keys from:
# - Sonarr: Settings → General → API Key
# - Radarr: Settings → General → API Key
nano configarr/secrets.yml
```

### Included Profiles (TRaSH-Guides)

| Profile | Quality | Use Case |
|---------|---------|----------|
| WEB-1080p | 1080p streaming | Standard TV shows |
| WEB-2160p | 4K streaming | 4K TV shows (HDR/DV) |
| HD Bluray + WEB | 1080p | Standard movies |
| UHD Bluray + WEB | 4K | 4K movies (HDR/DV) |

### Scheduling (Optional)

Add to host crontab to run weekly:

```bash
# Edit crontab
crontab -e

# Add line (runs every Monday at 4 AM)
0 4 * * 1 cd /home/mircea/homeserver/media-server && docker compose run --rm configarr >> /home/mircea/docker/configarr/configarr.log 2>&1
```

### Switching to 4K

After running Configarr, new quality profiles will appear in Sonarr/Radarr:
1. Go to **Movies/Series → Edit** (or bulk edit)
2. Change **Quality Profile** to `UHD Bluray + WEB` (movies) or `WEB-2160p` (TV)
3. Optionally trigger a search for upgrades

### Upgrading Quality Profiles

#### Via Web UI (Manual)

**Bulk update multiple movies/shows:**
1. **Movies** (or **Series**) → Select items using checkboxes
2. Click **Edit** in the bottom toolbar
3. Change **Quality Profile** → Select desired profile
4. Click **Save**

**Trigger upgrade search:**
1. **Wanted → Cutoff Unmet** - shows everything below target quality
2. Select items → **Search Selected**

#### Via API

See [API Commands](#api-commands) section for `CutoffUnmetMoviesSearch`.

## Accessing Services

All services are accessible via Cloudflare Tunnel:
- `qbittorrent.home-server.me`
- `sonarr.home-server.me`
- `radarr.home-server.me`
- `prowlarr.home-server.me`
- `seerr.home-server.me`
- `pulsarr.home-server.me`
- `plex.home-server.me`

Or locally via `http://homelab:<port>`.

## Pulsarr Setup

Pulsarr is deployed in parallel with Seerr and is intended to become the primary Plex watchlist automation service after validation.

### Runtime Configuration

The container runtime is configured in `compose.yml` with environment variables:

- `baseUrl=http://pulsarr`
- `port=3003`
- `listenPort=3003`
- `dbPath=./data/db/pulsarr.db`
- `cookieSecured=false`

This is intentionally only the runtime layer. Pulsarr uses a hybrid model where the app state is configured in the web UI and persisted under `${DOCKER_DATA}/pulsarr`.

### URLs

- Local UI: `http://homelab:3003`
- Public UI: `https://pulsarr.home-server.me`
- API docs: `http://homelab:3003/api/docs`

### One-Time UI Bootstrap

1. Open Pulsarr and create the initial admin account.
2. Connect Plex and enable user sync for the Plex users you want to process.
3. Add Sonarr and Radarr instances using Docker network URLs:
   - `http://radarr:7878`
   - `http://sonarr:8989`
   - `http://sonarr-anime:8989`
4. Configure Pulsarr approval defaults to auto-approve for the synced users in the initial rollout.
5. Start the main watchlist workflow from the Pulsarr dashboard and enable auto-start.

### Routing Rules

Configure the following initial routes:

1. Sonarr fallback/default route → `sonarr`
2. Higher-priority anime route → `sonarr-anime`
3. Radarr fallback/default route → `radarr`

The anime route should be placed above the fallback Sonarr route so anime watchlist additions land in the Anime Sonarr instance instead of the general TV instance.

### Seerr Cutover Step

Seerr remains installed during validation for request history and status tracking, but it must not continue creating watchlist requests in parallel.

After Pulsarr is fully configured:

1. Open Seerr
2. Go to the Plex watchlist auto-request permissions/settings for the relevant users
3. Disable Seerr watchlist auto-request
4. Keep Seerr service integrations and scans enabled so existing request status tracking still works during the transition

### Validation Checklist

- Add one normal TV show to a Plex watchlist and confirm it lands in `sonarr`
- Add one anime series and confirm it lands in `sonarr-anime`
- Add one movie and confirm it lands in `radarr`
- Confirm the request is auto-approved and executed immediately
- Confirm Seerr does not create a duplicate watchlist request after its auto-request setting is disabled
