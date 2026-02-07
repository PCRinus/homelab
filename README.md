# Homelab Docker Compose

Self-hosted homelab running Docker on Linux. Services are organized into stacks, each with its own `compose.yml`.

## Prerequisites

- **Linux server** (tested on Ubuntu)
- **zsh** — shell environment (the init script writes to `~/.zshenv`)
- **Docker Engine** with Docker Compose v2 plugin
- **Git** — to clone and manage this repo
- **NAS mount** — media storage mounted at a local path (e.g., `/mnt/unas/media`)

### Installing Docker

```bash
# Install Docker Engine (standard, non-rootless)
# https://docs.docker.com/engine/install/ubuntu/
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group (logout/login after)
sudo usermod -aG docker $USER
```

### Installing zsh

```bash
# Ubuntu/Debian
sudo apt install -y zsh

# Set as default shell
chsh -s $(which zsh)
```

## Quick Start

```bash
# 1. Clone the repo
git clone <repo-url> ~/compose-files
cd ~/compose-files

# 2. Run the setup script
./init.sh

# 3. Load the new environment
source ~/.zshenv

# 4. Fill in your secrets
nano .env   # API keys, passwords, tokens — see .env.example

# 5. Create the shared Docker network
docker network create media-net

# 6. Start a stack
cd media-server && docker compose up -d
```

## What `init.sh` Does

The setup script interactively configures machine-specific paths and writes them to `~/.zshenv`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `DOCKER_DATA` | Container persistent data (configs, databases) | `~/docker` |
| `MEDIA_PATH` | NAS media storage mount point | `/mnt/unas/media` |
| `DOCKER_SOCK` | Docker socket path (auto-detected) | `/var/run/docker.sock` |

These are used by all `compose.yml` files via `${VARIABLE}` interpolation. Docker Compose reads them from the shell environment automatically.

Re-running `init.sh` is safe — it replaces the existing block in `~/.zshenv`.

## Service Stacks

| Directory | Services | Description |
|-----------|----------|-------------|
| `media-server/` | Plex, Jellyfin, Sonarr, Radarr, Prowlarr, qBittorrent, Overseerr, Bazarr, Tautulli, FlareSolverr | Media management and streaming |
| `cloudflare-tunnel/` | Cloudflared + watchdog | Zero Trust tunnel for external access |
| `homepage/` | Homepage dashboard | Service dashboard with widgets |
| `home-assistant/` | Home Assistant | Smart home automation |
| `monitoring/` | Dozzle, Gatus | Log viewer and uptime monitoring |
| `minecraft-servers/` | Fabric Minecraft servers | Game servers with shared mod configs |

## Secrets & Configuration

Secrets are **not** checked into git. After cloning, create these from their examples:

| File | Template | Purpose |
|------|----------|---------|
| `.env` | `.env.example` | API keys, credentials, common settings |
| `cloudflare-tunnel/tunnel-token` | — | Cloudflare tunnel auth token |
| `cloudflare-tunnel/terraform.tfvars` | — | Cloudflare zone/account IDs, OAuth secrets |
| `media-server/wg0.conf` | — | ProtonVPN WireGuard config |
| `media-server/buildarr/buildarr-secrets.yml` | `buildarr-secrets.yml.example` | Arr app API keys for Buildarr |
| `media-server/configarr/secrets.yml` | `secrets.yml.example` | Arr app API keys for Configarr |
| `home-assistant/secrets.yaml` | `secrets.yaml.example` | Home Assistant secrets |

## CI/CD

GitHub Actions deploy services via SSH over Tailscale when compose files change on `main`. See [.github/SETUP.md](.github/SETUP.md) for configuration.

## GPU Transcoding (Optional)

For hardware-accelerated transcoding in Plex/Jellyfin, the compose file passes through `/dev/dri`. You need:

```bash
# Check for a GPU
ls /dev/dri/

# Find the render group GID (used in compose.yml group_add)
getent group render
```

Update the `group_add` GID in `media-server/compose.yml` if it differs from `993`.

## Network

All services that need inter-container communication join the `media-net` external network:

```bash
docker network create media-net
```
