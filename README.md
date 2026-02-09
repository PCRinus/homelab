# Homelab Docker Compose

Self-hosted homelab running Docker on Linux. Services are organized into stacks, each with its own `compose.yml`.

## Prerequisites

- **Linux server** (tested on Ubuntu)
- **zsh** — shell environment (the init script writes to `~/.zshenv`)
- **Docker Engine** with Docker Compose v2 plugin
- **Git** — to clone and manage this repo
- **NAS mount** — media storage mounted at a local path (e.g., `/mnt/unas/media`)
- **sops** — secrets encryption ([install](https://github.com/getsops/sops/releases))
- **age** — encryption backend (`sudo apt install age` or [releases](https://github.com/FiloSottile/age/releases))

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
git clone <repo-url> ~/homeserver
cd ~/homeserver

# 2. Copy your age key (from old machine or password manager)
mkdir -p ~/.config/sops/age
cp /path/to/keys.txt ~/.config/sops/age/keys.txt

# 3. Run the setup script (configures paths + decrypts secrets)
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
| `DOCKER_SOCK` | Docker socket path (auto-detected) | `/var/run/docker.sock` |

These are used by all `compose.yml` files via `${VARIABLE}` interpolation. Docker Compose reads them from the shell environment automatically.

Re-running `scripts/init.sh` is safe — it replaces the existing block in `~/.zshenv`.

## Service Stacks

| Directory | Services | Description |
|-----------|----------|-------------|
| `media-server/` | Plex, Sonarr, Radarr, Prowlarr, qBittorrent, Overseerr, Bazarr, Tautulli, FlareSolverr | Media management and streaming |
| `cloudflare-tunnel/` | Cloudflared + watchdog | Zero Trust tunnel for external access |
| `homepage/` | Homepage dashboard | Service dashboard with widgets |
| `home-assistant/` | Home Assistant | Smart home automation |
| `monitoring/` | Dozzle, Gatus | Log viewer and uptime monitoring |
| `minecraft-servers/` | Fabric Minecraft servers | Game servers with shared mod configs |

## Secrets & Configuration

Secrets are encrypted in the repo using [sops](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age). Plaintext files are gitignored; encrypted `.enc` variants are tracked.

| Plaintext (gitignored) | Encrypted (tracked) | Method |
|------------------------|---------------------|--------|
| `.env` | `.env.enc` | sops |
| `cloudflare-tunnel/terraform.tfvars` | `...tfvars.enc` | sops |
| `home-assistant/secrets.yaml` | `...yaml.enc` | sops |
| `media-server/buildarr/buildarr-secrets.yml` | `...yml.enc` | sops |
| `media-server/configarr/secrets.yml` | `...yml.enc` | sops |
| `cloudflare-tunnel/tunnel-token` | `...token.enc` | age |
| `media-server/wg0.conf` | `...conf.enc` | age |

### Decrypt (after clone / on new machine)

```bash
./scripts/secrets.sh decrypt
```

`scripts/init.sh` runs this automatically if it finds your age key at `~/.config/sops/age/keys.txt`.

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
cp media-server/buildarr/buildarr-secrets.yml.example media-server/buildarr/buildarr-secrets.yml
cp media-server/configarr/secrets.yml.example media-server/configarr/secrets.yml
cp home-assistant/secrets.yaml.example home-assistant/secrets.yaml
# Fill in values, then encrypt:
./scripts/secrets.sh encrypt
```

> **Back up your age key** (`~/.config/sops/age/keys.txt`) — it's the one secret needed to unlock everything.

## Plex Integration Setup

For the fully automatic media pipeline to work (request → download → import → Plex library update → Overseerr status update), three pieces of integration must be configured in the service web UIs.

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

### 2. Overseerr → Sonarr / Radarr (Sync Scan)

Overseerr needs **Enable Scan** turned on for each Sonarr and Radarr server so it can poll their state and transition requests from "Requested" to "Available".

1. Go to **Settings → Services → Radarr Servers** → edit the `radarr` server entry
   - Toggle **Enable Scan** on → Save
2. Go to **Settings → Services → Sonarr Servers** → edit each server (`sonarr`, `Sonarr Anime`)
   - Toggle **Enable Scan** on → Save

Without this, Overseerr's periodic Radarr/Sonarr scan jobs will log `Sync not enabled. Skipping...` and requests will stay stuck as "Requested" forever.

### 3. Overseerr → Plex (Recently Added Scan)

This should already be configured if Overseerr was set up with Plex as the media server. Verify under **Settings → Plex** that your Plex server is connected and libraries (Movies, TV Shows, Anime) are all enabled for scanning.

The **Plex Recently Added Scan** job runs every 5 minutes by default and detects newly added content. If content was missed (e.g., after re-enabling sync), use **Run Full Scan** from Settings → Plex to re-index everything.

### End-to-End Flow

```
User requests media in Overseerr
  → Overseerr sends request to Sonarr/Radarr
    → Sonarr/Radarr searches via Prowlarr and sends to qBittorrent
      → qBittorrent downloads, Sonarr/Radarr imports to media folder
        → Sonarr/Radarr notifies Plex via Connect (step 1)
          → Plex scans library and picks up new file
            → Overseerr's Plex Recently Added Scan detects it (step 3)
              → Overseerr's Sonarr/Radarr Scan confirms download status (step 2)
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
