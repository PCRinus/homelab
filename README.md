# Homelab Docker Compose

Self-hosted homelab running Docker on Linux. Services are organized into stacks, each with its own `compose.yml`.

## Prerequisites

- **Linux server** (tested on Ubuntu)
- **zsh** — required shell environment (the init script writes to `~/.zshenv` and this repo’s VS Code workspace defaults integrated terminals to zsh)
- **Docker Engine** with Docker Compose v2 plugin
- **Git** — to clone and manage this repo
- **NAS mount** — media storage mounted at a local path (e.g., `/mnt/unas/media`)
- **Optional backup NAS mount** — container backup storage (e.g., `/mnt/unas/container-backups`)
- **sops** — secrets encryption ([install](https://github.com/getsops/sops/releases))
- **age** — encryption backend (`sudo apt install age` or [releases](https://github.com/FiloSottile/age/releases))

### Installing Docker

```bash
# Install Docker Engine (standard, rootful mode)
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
git clone <repo-url> ~/homeserver
cd ~/homeserver

# 2. Copy your age key (from old machine or password manager)
mkdir -p ~/.config/sops/age
cp /path/to/keys.txt ~/.config/sops/age/keys.txt

# 3. Run the setup script (configures paths and host settings)
./scripts/init.sh

# 4. Load the new environment
source ~/.zshenv

# 5. Create the shared Docker network
docker network create media-net

# 6. Start all services
./scripts/start.sh
```

For a **fresh setup** with no existing secrets, skip step 2 and create secrets manually from examples (see Secrets section).

## What `scripts/init.sh` Does

The setup script interactively configures machine-specific paths and writes them to `~/.zshenv`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `DOCKER_DATA` | Container persistent data (configs, databases) | `~/docker` |
| `MEDIA_PATH` | NAS media storage mount point | `/mnt/unas/media` |
| `QBITTORRENT_INCOMPLETE_PATH` | Local staging path for active qBittorrent downloads | `~/docker/qbittorrent/incomplete` |
| `DOCKER_SOCK` | Docker socket path (auto-detected) | `/var/run/docker.sock` |

These are used by all `compose.yml` files via `${VARIABLE}` interpolation. Docker Compose reads them from the shell environment automatically.
`QBITTORRENT_INCOMPLETE_PATH` is intentionally local so active torrent writes do not fail when the NAS mount stalls.

Re-running `scripts/init.sh` is safe — it replaces the existing block in `~/.zshenv`.

## Container Backups (Seerr / Pulsarr)

Set up a dedicated NAS mount for backups:

```bash
./scripts/setup-container-backups-mount.sh
```

This is a preset wrapper around `scripts/setup-nas-mount.sh` with:
- mount point default: `/mnt/unas/container-backups`
- share default: `ContainerBackups`

Create a backup manually:

```bash
./scripts/backup-seerr.sh
./scripts/backup-pulsarr.sh
```

Defaults:
- Seerr backup target: `/mnt/unas/container-backups/seerr`
- Pulsarr backup target: `/mnt/unas/container-backups/pulsarr`
- retention: `30` days

Override defaults when needed:

```bash
BACKUP_MOUNT_PATH=/mnt/unas/container-backups BACKUP_RETENTION_DAYS=14 ./scripts/backup-seerr.sh
BACKUP_MOUNT_PATH=/mnt/unas/container-backups BACKUP_RETENTION_DAYS=14 ./scripts/backup-pulsarr.sh
```

Automated backups run via GitHub Actions workflows `.github/workflows/backup-seerr.yml` and `.github/workflows/backup-pulsarr.yml` every 3 days.
You can override the remote backup path and retention with repository variables:
- `HOMELAB_BACKUP_PATH`
- `HOMELAB_BACKUP_RETENTION_DAYS`

## Migration

Host-to-host migration is documented as a runbook rather than an automation script.
See [specs/migration-runbook.md](specs/migration-runbook.md) for the recommended backup/restore and `rsync`-based approaches.

## Service Stacks

| Directory | Services | Description |
|-----------|----------|-------------|
| `media-server/` | Plex, Sonarr, Radarr, Prowlarr, qBittorrent, Seerr, Pulsarr, Bazarr, Tautulli, FlareSolverr | Media management and streaming |
| `cloudflare-tunnel/` | Cloudflared + watchdog | Zero Trust tunnel for external access |
| `homepage/` | Homepage dashboard | Service dashboard with widgets |
| `home-assistant/` | Home Assistant | Smart home automation |
| `monitoring/` | Dozzle, Gatus | Log viewer and uptime monitoring |
| `minecraft-servers/` | Fabric Minecraft servers | Game servers with shared mod configs |

## Secrets & Configuration

Secrets are encrypted in the repo using [sops](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age). Plaintext files are gitignored; encrypted `.enc` variants are tracked.
Runtime now prefers `.env.enc` and decrypts it to a temporary file for Compose when available. Plaintext `.env` is still useful for editing and bootstrap, but it is no longer the preferred runtime source.

| Plaintext (gitignored) | Encrypted (tracked) | Method |
|------------------------|---------------------|--------|
| `.env` | `.env.enc` | sops |
| `cloudflare-tunnel/terraform.tfvars` | `...tfvars.enc` | sops |
| `home-assistant/secrets.yaml` | `...yaml.enc` | sops |
| `media-server/configarr/secrets.yml` | `...yml.enc` | sops |
| `cloudflare-tunnel/tunnel-token` | `...token.enc` | age |
| `media-server/wg0.conf` | `...conf.enc` | age |

### Decrypt (only when you need plaintext for editing or inspection)

```bash
./scripts/secrets.sh decrypt
```

Runtime does not require decrypting `.env.enc` first. The Compose wrapper decrypts it to a temporary file when needed.

### Encrypt (after editing a secret)

```bash
./scripts/secrets.sh encrypt
git add -A '*.enc'
git commit -m "Update secrets"
```

### Check status

```bash
./scripts/secrets.sh status
```

### First-time setup (no existing secrets)

Generate an age keypair and create secrets from examples:

```bash
age-keygen -o ~/.config/sops/age/keys.txt
cp .env.example .env
cp media-server/configarr/secrets.yml.example media-server/configarr/secrets.yml
cp home-assistant/secrets.yaml.example home-assistant/secrets.yaml
# Fill in values, then encrypt:
./scripts/secrets.sh encrypt
```

> **Back up your age key** (`~/.config/sops/age/keys.txt`) — it's the one secret needed to unlock everything.

## Plex Integration Setup

For the fully automatic media pipeline to work (watchlist request → download → import → Plex library update → request status update), the service web UIs need a small amount of post-deploy configuration.

### 1. Sonarr / Radarr → Plex (Library Scan on Import)

Each *arr instance needs a **Plex Media Server** connection so that when a download finishes and gets imported, it tells Plex to scan the relevant library. Without this, files land on disk but Plex never knows they're there.

Configure in **each** of Sonarr (`localhost:8989`), Sonarr Anime (`localhost:8990`), and Radarr (`localhost:7878`):

1. Go to **Settings → Connect → +** → select **Plex Media Server**
2. Fill in:
   - **Host:** `plex` (Docker container name — works because all services share `media-net`)
   - **Port:** `32400`
   - **Auth Token:** your Plex token (see below)
   - **Update Library:** enabled
3. Under **Notification Triggers**, enable:
   - **On Import** (fires when a download is moved to the media folder)
   - **On Upgrade** (fires when a higher-quality version replaces an existing file)
4. Click **Test** to verify the connection, then **Save**

> **Getting your Plex token:** Open Plex web → navigate to any media item → click `⋮` → Get Info → View XML. The `X-Plex-Token` parameter in the URL is your token. Alternatively, extract it from:
> ```bash
> grep -oP 'PlexOnlineToken="\K[^"]+' "$DOCKER_DATA/plex/config/Library/Application Support/Plex Media Server/Preferences.xml"
> ```

### 2. Seerr → Sonarr / Radarr (Sync Scan)

Seerr needs **Enable Scan** turned on for each Sonarr and Radarr server so it can poll their state and transition requests from "Requested" to "Available".

1. Go to **Settings → Services → Radarr Servers** → edit the `radarr` server entry
   - Toggle **Enable Scan** on → Save
2. Go to **Settings → Services → Sonarr Servers** → edit each server (`sonarr`, `Sonarr Anime`)
   - Toggle **Enable Scan** on → Save

Without this, Seerr's periodic Radarr/Sonarr scan jobs will log `Sync not enabled. Skipping...` and requests will stay stuck as "Requested" forever.

### 3. Seerr → Plex (Recently Added Scan)

This should already be configured if Seerr was set up with Plex as the media server. Verify under **Settings → Plex** that your Plex server is connected and libraries (Movies, TV Shows, Anime) are all enabled for scanning.

The **Plex Recently Added Scan** job runs every 5 minutes by default and detects newly added content. If content was missed (e.g., after re-enabling sync), use **Run Full Scan** from Settings → Plex to re-index everything.

### 4. Pulsarr Parallel Rollout

Pulsarr now runs alongside Seerr and is intended to become the watchlist-driven request path. During the validation phase:

1. Finish the Pulsarr bootstrap in the web UI:
   - local URL: `http://homelab:3003`
   - public URL: `https://pulsarr.home-server.me`
2. In Pulsarr, create the admin account and configure:
   - **Plex** user sync
   - **Radarr** at `http://radarr:7878`
   - **Sonarr TV** at `http://sonarr:8989`
   - **Sonarr Anime** at `http://sonarr-anime:8989`
3. Configure routing rules:
   - Sonarr fallback/default route → `sonarr`
   - Anime route with higher priority → `sonarr-anime`
   - Radarr fallback/default route → `radarr`
4. Set Pulsarr's default approval behavior to auto-approve for the synced users used in the initial rollout.
5. After Pulsarr is ready, disable Seerr's Plex watchlist auto-request permissions so both services do not react to the same watchlist additions.

Pulsarr uses a hybrid configuration model:
- container/runtime settings are file-driven through Docker Compose environment variables
- application state such as Plex, Sonarr, Radarr, routing, and approvals is configured in the Pulsarr UI and persisted in `/app/data`
- if stronger automation is needed later, Pulsarr also exposes a REST API at `/api/docs`

### End-to-End Flow

```
User adds media to a Plex watchlist
  → Pulsarr syncs the watchlist and applies routing rules
    → Pulsarr sends request to Sonarr/Radarr
    → Sonarr/Radarr searches via Prowlarr and sends to qBittorrent
      → qBittorrent downloads, Sonarr/Radarr imports to media folder
        → Sonarr/Radarr notifies Plex via Connect (step 1)
          → Plex scans library and picks up new file
            → Seerr's Plex Recently Added Scan detects it (step 3)
              → Seerr's Sonarr/Radarr Scan confirms download status (step 2)
                → Request status updates to "Available"
```

## CI/CD

GitHub Actions deploy services via SSH over Tailscale when compose files change on `main`. See [.github/SETUP.md](.github/SETUP.md) for configuration.

Set the `HOMELAB_REPO_DIR` repository variable in GitHub to the absolute path of the repo on the server (e.g., `/home/mircea/homeserver`).
Set the `HOMELAB_SSH_HOST` repository variable to the SSH host (or alias) of the target server.

## GPU Transcoding (Optional)

For hardware-accelerated transcoding in Plex, the compose file passes through `/dev/dri`. You need:

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
