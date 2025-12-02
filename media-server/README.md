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
| Overseerr | 5055 | Media request system |
| Plex | 32400 | Media server |
| FlareSolverr | 8191 | Cloudflare bypass for indexers |
| Buildarr | - | Configuration management for *arr stack |

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
cd /home/mircea/compose-files/media-server
./start.sh
```

### Authentication

WebUI credentials are set via environment variables in `.env`:
- `QBITTORRENT_USER`
- `QBITTORRENT_PASS`

### First-Time Setup

On first launch, qBittorrent generates a temporary password. Check the logs:
```bash
docker logs qbittorrent
```

Then log in and set your permanent credentials via **Tools → Options → Web UI**.

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
│  Overseerr  │────▶│ Sonarr/     │────▶│    qBittorrent      │
│  (request)  │     │ Radarr      │     │    (download)       │
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
├── torrents/
│   ├── incomplete/              # Active downloads (qBittorrent)
│   ├── movies/                  # Completed movie torrents (seeding)
│   └── tv/                      # Completed TV torrents (seeding)
└── media/
    ├── movies/                  # Movie library (Plex)
    └── tv/                      # TV library (Plex)
```

### How Downloads Are Organized

qBittorrent uses **categories** to organize downloads. Configure categories in Sonarr/Radarr:

| App | Category | Save Path |
|-----|----------|-----------|
| Sonarr | `tv-sonarr` | `/data/torrents/tv` |
| Radarr | `radarr` | `/data/torrents/movies` |

### Hardlinks

Since `/data/torrents` and `/data/media` are on the same filesystem (NAS), Sonarr/Radarr use **hardlinks** when importing. This means:
- Instant "moves" (no copying)
- Files exist in both locations but use disk space only once
- qBittorrent keeps seeding from `torrents/` while Plex serves from `media/`

## API Commands

Useful API commands for managing the *arr stack. Source the `.env` file first to get API keys:

```bash
source /home/mircea/compose-files/.env
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
cd /home/mircea/compose-files/media-server && docker compose stop bazarr

# Edit config (use container for rootless Docker permissions)
docker run --rm -v /home/mircea/docker/bazarr/config:/config alpine \
  sed -i 's|server_url: https://.*plex.direct:32400|server_url: http://plex:32400|' /config/config.yaml

# Verify the change
grep "server_url" /home/mircea/docker/bazarr/config/config.yaml
# Should show: server_url: http://plex:32400

# Start Bazarr
docker compose start bazarr
```

This changes the connection from `https://*.plex.direct:32400` (external, can timeout) to `http://plex:32400` (internal Docker network, fast and reliable).

## Buildarr

Buildarr manages configuration for Sonarr and Prowlarr. See `buildarr/README.md` for details.

**Note:** Download client configuration is managed manually in Sonarr/Radarr due to Buildarr plugin limitations with password serialization.

## Accessing Services

All services are accessible via Cloudflare Tunnel:
- `qbittorrent.home-server.me`
- `sonarr.home-server.me`
- `radarr.home-server.me`
- `prowlarr.home-server.me`
- `overseerr.home-server.me`
- `plex.home-server.me`

Or locally via `http://homelab:<port>`.
