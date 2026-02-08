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
git clone <repo-url> ~/compose-files
cd ~/compose-files

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

## CI/CD

GitHub Actions deploy services via SSH over Tailscale when compose files change on `main`. See [.github/SETUP.md](.github/SETUP.md) for configuration.

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
