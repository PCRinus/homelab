# Media Server Stack

This directory contains the Docker Compose configuration for the media server stack.

## Services

| Service | Port | Description |
|---------|------|-------------|
| Gluetun | 8000 (control) | VPN client (ProtonVPN) - routes qBittorrent traffic |
| qBittorrent | 8080 | Torrent client (via Gluetun VPN) |
| Sonarr | 8989 | TV series management |
| Radarr | 7878 | Movie management |
| Prowlarr | 9696 | Indexer manager |
| Bazarr | 6767 | Subtitle management |
| Overseerr | 5055 | Media request system |
| Plex | 32400 | Media server |
| FlareSolverr | 8191 | Cloudflare bypass for indexers |
| Buildarr | - | Configuration management for *arr stack |

## VPN Setup (Gluetun + ProtonVPN)

All torrent traffic is routed through ProtonVPN via Gluetun. This protects your IP and enables seeding via ProtonVPN's port forwarding.

### How It Works

- **Gluetun** creates a VPN tunnel to ProtonVPN using WireGuard
- **qBittorrent** uses `network_mode: service:gluetun` to route all traffic through the VPN
- **Port forwarding** is automatic - Gluetun obtains a forwarded port from ProtonVPN

### Configuration

VPN credentials are in `.env`:
- `WIREGUARD_PRIVATE_KEY` - Get from https://account.protonvpn.com/downloads (WireGuard config)
- `SERVER_COUNTRIES` - Server location (default: Netherlands, must support P2P + port forwarding)

### Checking VPN Status

```bash
# Check if VPN is connected
docker exec gluetun wget -qO- ifconfig.me

# Check forwarded port
cat /home/mircea/docker/gluetun/forwarded_port

# View Gluetun logs
docker logs gluetun
```

### Port Forwarding for Seeding

Gluetun automatically obtains a forwarded port from ProtonVPN and writes it to `/home/mircea/docker/gluetun/forwarded_port`. Configure qBittorrent to use this port:

1. Check the port: `cat /home/mircea/docker/gluetun/forwarded_port`
2. In qBittorrent: **Settings → Connection → Listening Port**
3. Set the port to match the forwarded port

**Note:** The forwarded port may change when Gluetun reconnects. For automation, consider using Gluetun's control server API.

## Torrent Client Setup (qBittorrent)

### Configuration

qBittorrent stores its configuration in `/home/mircea/docker/qbittorrent/`. Settings are managed via the WebUI.

**Key settings:**
- Download directory: `/data/torrents`
- Incomplete directory: `/data/torrents/incomplete`
- WebUI port: 8080
- Peer port: (use forwarded port from Gluetun)

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
