# Media Server Stack

This directory contains the Docker Compose configuration for the media server stack.

## Services

| Service | Port | Description |
|---------|------|-------------|
| Transmission | 9091 | Torrent client |
| Sonarr | 8989 | TV series management |
| Radarr | 7878 | Movie management |
| Prowlarr | 9696 | Indexer manager |
| Bazarr | 6767 | Subtitle management |
| Overseerr | 5055 | Media request system |
| Plex | 32400 | Media server |
| FlareSolverr | 8191 | Cloudflare bypass for indexers |
| Buildarr | - | Configuration management for *arr stack |

## Torrent Client Setup (Transmission)

### Configuration

Transmission is configured via `transmission/settings.json`, which is version-controlled and mounted read-only into the container.

**Key settings:**
- Download directory: `/data/torrents`
- Incomplete directory: `/data/torrents/incomplete`
- WebUI port: 9091
- Peer port: 51413 (not exposed externally)

**Speed limits (always-on):**
- Download: 50 MB/s (400 Mbps)
- Upload: 10 MB/s (80 Mbps)
- Active downloads: 8 concurrent
- Seed queue: 10 torrents

### Authentication

WebUI credentials are set via environment variables in `.env`:
- `TRANSMISSION_USER`
- `TRANSMISSION_PASS`

**Do not** set `rpc-username` or `rpc-password` in `settings.json` — the LinuxServer container handles this via env vars.

### WebUI (Flood)

We use [Flood for Transmission](https://github.com/johman10/flood-for-transmission) — a modern, dark-themed UI.

**Installation location:** `/home/mircea/docker/transmission/flood-for-transmission/`

This is mounted into the container at `/config/flood-for-transmission/` and set via:
```yaml
environment:
  - TRANSMISSION_WEB_HOME=/config/flood-for-transmission/
```

**Note:** LinuxServer no longer bundles third-party UIs, so Flood is installed manually to the config directory where it persists across container updates.

**To update Flood:**
```bash
cd /tmp
curl -OL https://github.com/johman10/flood-for-transmission/releases/download/latest/flood-for-transmission.zip
unzip flood-for-transmission.zip
sudo rm -rf /home/mircea/docker/transmission/flood-for-transmission
sudo mv flood-for-transmission /home/mircea/docker/transmission/
sudo chown -R 1000:1000 /home/mircea/docker/transmission/flood-for-transmission
rm flood-for-transmission.zip
# Restart Transmission
cd /home/mircea/compose-files/media-server && docker compose restart transmission
```

**Alternative UIs:** To switch to a different UI, download it to the config directory and update `TRANSMISSION_WEB_HOME`:
- [Combustion](https://github.com/Secretmapper/combustion)
- [Transmission Web Control](https://github.com/ronggang/transmission-web-control)

## Media Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────────────┐
│  Overseerr  │────▶│ Sonarr/     │────▶│    Transmission     │
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
│   ├── incomplete/              # Active downloads (Transmission)
│   ├── movies/                  # Completed movie torrents (seeding)
│   └── tv/                      # Completed TV torrents (seeding)
└── media/
    ├── movies/                  # Movie library (Plex)
    └── tv/                      # TV library (Plex)
```

### How Downloads Are Organized

Transmission doesn't have categories like qBittorrent. Instead, Sonarr/Radarr specify the download directory per-torrent:

| App | Download Directory |
|-----|-------------------|
| Sonarr | `/data/torrents/tv` |
| Radarr | `/data/torrents/movies` |

Configure this in each app under **Settings → Download Clients → Transmission → Directory**.

### Hardlinks

Since `/data/torrents` and `/data/media` are on the same filesystem (NAS), Sonarr/Radarr use **hardlinks** when importing. This means:
- Instant "moves" (no copying)
- Files exist in both locations but use disk space only once
- Transmission keeps seeding from `torrents/` while Plex serves from `media/`

## Buildarr

Buildarr manages configuration for Sonarr and Prowlarr. See `buildarr/README.md` for details.

**Note:** Download client configuration is managed manually in Sonarr/Radarr due to Buildarr plugin limitations with password serialization.

## Accessing Services

All services are accessible via Cloudflare Tunnel:
- `transmission.home-server.me`
- `sonarr.home-server.me`
- `radarr.home-server.me`
- `prowlarr.home-server.me`
- `overseerr.home-server.me`
- `plex.home-server.me`

Or locally via `http://homelab:<port>`.
