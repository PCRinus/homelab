# Docker Rootless Migration Guide

Migration Date: November 16, 2025
User: mircea
Server: homelab

## Pre-Migration State

- Docker Version: 28.4.0 (snap)
- Installation Type: snap
- Containers Running: 13

**Running Containers:**
```
NAMES           IMAGE                                        STATUS
cloudflared     cloudflare/cloudflared:2025.11.1             Restarting (1) 40 seconds ago
uptime-kuma     louislam/uptime-kuma:2                       Up 4 hours (healthy)
qbittorrent     lscr.io/linuxserver/qbittorrent:20.04.1      Up 47 hours
plex            lscr.io/linuxserver/plex:1.42.2              Up 47 hours
flaresolverr    ghcr.io/flaresolverr/flaresolverr:v3.4.5     Up 47 hours
homepage        ghcr.io/gethomepage/homepage:v1.7            Up 47 hours (healthy)
prowlarr        ghcr.io/hotio/prowlarr:release-1.27.0.4852   Up 2 days
sonarr          ghcr.io/hotio/sonarr:release-4.0.11.2680     Up 2 days
radarr          ghcr.io/hotio/radarr:release-5.14.0.9383     Up 2 days
dozzle          amir20/dozzle:v8.14.7                        Up 2 days
portainer       portainer/portainer-ce:lts                   Up 7 days
overseerr       sctx/overseerr:develop                       Up 7 days
homeassistant   lscr.io/linuxserver/homeassistant:latest     Up 7 days
```

**Docker Volumes:**
```
dede09f25ef5880d8b937ecf22c84265d30c005454c121322d3df656bcf68b4a (unnamed)
media-server_external_drive
minecraft-server-survival-island_data
minecraft-server-world-generation_data
minecraft-server_data
portainer_data
```

- Services:
  - portainer
  - dozzle
  - home-assistant
  - homepage
  - media-server (plex, qbittorrent, sonarr, radarr, prowlarr, overseerr, flaresolverr)
  - minecraft-servers
  - uptime-kuma
  - cloudflare-tunnel

## Migration Steps

### Step 1: Document Current State ✅

List all running containers:
```bash
sudo docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

List all volumes:
```bash
sudo docker volume ls
```

### Step 2: Stop All Containers

Stop containers in each service directory:
```bash
cd ~/compose-files/portainer && sudo docker compose down
cd ~/compose-files/dozzle && sudo docker compose down
cd ~/compose-files/home-assistant && sudo docker compose down
cd ~/compose-files/homepage && sudo docker compose down
cd ~/compose-files/media-server && sudo docker compose down
cd ~/compose-files/minecraft-servers && sudo docker compose down
cd ~/compose-files/uptime-kuma && sudo docker compose down
cd ~/compose-files/cloudflare-tunnel && sudo docker compose down
```

Verify all stopped:
```bash
sudo docker ps -a
```

### Step 3: Remove Snap Docker

Remove the snap Docker installation:
```bash
sudo snap remove docker --purge
```

Verify removal:
```bash
which docker  # Should return nothing
```

### Step 4: Install Rootless Docker

Install prerequisites:
```bash
sudo apt-get update
sudo apt-get install -y uidmap dbus-user-session
```

Install Docker rootless:
```bash
curl -fsSL https://get.docker.com/rootless | sh
```

### Step 5: Configure Rootless Docker

Add Docker to PATH (add to ~/.zshrc or ~/.bashrc):
```bash
export PATH=/home/mircea/bin:$PATH
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
```

Apply environment variables:
```bash
source ~/.zshrc
```

Enable Docker service to start on boot:
```bash
systemctl --user enable docker
systemctl --user start docker
```

Verify Docker works without sudo:
```bash
docker version
docker ps
```

### Step 6: Recreate All Containers

Start all services (NO SUDO needed now!):
```bash
cd ~/compose-files/portainer && docker compose up -d
cd ~/compose-files/dozzle && docker compose up -d
cd ~/compose-files/home-assistant && docker compose up -d
cd ~/compose-files/homepage && docker compose up -d
cd ~/compose-files/media-server && docker compose up -d
cd ~/compose-files/minecraft-servers && docker compose up -d
cd ~/compose-files/uptime-kuma && docker compose up -d
cd ~/compose-files/cloudflare-tunnel && ./start.sh  # Uses custom script
```

### Step 7: Verify Everything Works

Check all containers are running:
```bash
docker ps
```

Test services are accessible:
- Check each service's port/URL
- Verify data is intact
- Test GitHub Actions workflow

## Post-Migration Verification

- [ ] All 13 containers running without sudo
- [ ] Services accessible on their ports
- [ ] Volumes/data intact
- [ ] GitHub Actions workflow succeeds
- [ ] No sudo needed for docker commands

## Rollback Plan (if needed)

If something goes wrong:

1. Stop rootless Docker:
```bash
systemctl --user stop docker
```

2. Reinstall snap Docker:
```bash
sudo snap install docker
```

3. Start containers with sudo again:
```bash
cd ~/compose-files/portainer && sudo docker compose up -d
# ... repeat for all services
```

## Notes

- Docker volumes are stored in: `~/.local/share/docker/`
- Docker config: `~/.config/docker/`
- Logs: `journalctl --user -u docker`
- Port restrictions: Ports < 1024 require sysctl configuration (if needed)

## Benefits Achieved

- ✅ No sudo required for Docker commands
- ✅ GitHub Actions can deploy without special permissions
- ✅ Better security isolation
- ✅ Simpler workflow configuration
