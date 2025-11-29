# Copilot Instructions for Homelab Repository

## Architecture Overview
Self-hosted homelab running Docker in **rootless mode** on Linux. Services are organized in separate directories, each with its own `compose.yml`. All services connect via the `media-net` Docker network for internal communication.

**Key paths:**
- Compose files: `/home/mircea/compose-files/<service>/`
- Container data: `/home/mircea/docker/<service>/` (persistent state, databases, cache)
- NAS media storage: `/mnt/unas/media/` (torrents at `/torrents`, media at `/media/`)

## Service Stacks

| Stack | Purpose | Key Files |
|-------|---------|-----------|
| `media-server/` | Plex, Sonarr, Radarr, Prowlarr, Transmission, Overseerr, FlareSolverr | `compose.yml`, `buildarr/buildarr.yml` |
| `cloudflare-tunnel/` | Zero Trust tunnel + Terraform for DNS/R2 | `compose.yml`, `*.tf` |
| `homepage/` | Dashboard aggregating all services | Config yamls mounted read-only |
| `home-assistant/` | Smart home automation | Configs mounted from repo |
| `minecraft-servers/` | Fabric servers with shared mods via YAML anchors | `common.compose.yml` + per-server files |
| `monitoring/` | Dozzle (logs) + Gatus (uptime) | `config.yaml` for Gatus |

## Docker Compose Patterns

**Environment variables:** Use root-level `.env` file via `env_file: - ../.env`. Contains `PUID`, `PGID`, `TZ`, API keys. Never hardcode secrets.

**Volume pattern:**
```yaml
volumes:
  - /home/mircea/docker/<service>:/config  # Persistent data
  - /mnt/unas/media:/data                   # NAS mount (media stack)
  - ./config.yaml:/app/config.yaml:ro       # Version-controlled configs
```

**Network pattern:** Services join `media-net` (external network) for inter-container communication:
```yaml
networks:
  media-net:
    external: true
```

**Rootless Docker specifics:**
- Docker socket at `/run/user/1000/docker.sock` (not `/var/run/docker.sock`)
- No privileged mode or host networking (except Home Assistant which uses `network_mode: host`)
- Use `extra_hosts: ["host.docker.internal:host-gateway"]` to reach host services

## File Conventions
- Compose files: `compose.yml` (not `docker-compose.yml`)
- Secrets pattern: `secrets.yaml` (gitignored) + `secrets.yaml.example` (committed)
- Pin image versions explicitly (e.g., `lscr.io/linuxserver/plex:1.42.2`)

## Startup Commands
```bash
# Media stack (uses start.sh to copy Transmission settings first)
cd /home/mircea/compose-files/media-server && ./start.sh

# Most services
cd /home/mircea/compose-files/<service> && docker compose up -d

# Minecraft (specify the server file)
docker compose -f survival-island.compose.yml up -d
```

## Buildarr (Configuration as Code)
Manages Sonarr/Prowlarr settings declaratively. Runs daily at 3 AM.
- Config: `media-server/buildarr/buildarr.yml`
- Secrets: `buildarr-secrets.yml` (gitignored)
- Test changes: `docker compose run --rm buildarr test-config`
- Dump current: `docker compose run --rm buildarr sonarr dump-config http://sonarr:8989`

## Terraform (Cloudflare)
Manages DNS, tunnel ingress rules, R2 storage. State stored in R2.
```bash
cd cloudflare-tunnel
export CLOUDFLARE_API_TOKEN="..." AWS_ACCESS_KEY_ID="..." AWS_SECRET_ACCESS_KEY="..."
terraform plan && terraform apply
```

## Renovate (Dependency Updates)
Renovate runs weekly (Mondays) to create PRs for outdated Docker images and Terraform providers. Pin image tags to specific versions (not `latest` or `develop`) so Renovate can detect updates:
```yaml
# Good - Renovate can update this
image: lscr.io/linuxserver/plex:1.42.2

# Bad - rolling tag, Renovate can't track
image: ghcr.io/sct/overseerr:develop
```

## Debugging & Logs
- **Web UI:** Dozzle at `monitoring/` provides real-time log streaming
- **CLI:** `docker compose logs -f <service>` for tailing logs when debugging

## When Making Changes
- Check existing patterns in similar services before suggesting new approaches
- Preserve `restart: unless-stopped` on all production services
- Add DNS entries (`dns: [1.1.1.1, 1.0.0.1, 8.8.8.8]`) for services needing external resolution
- Add comments for non-obvious port mappings
- For multi-step tasks: present numbered plan, keep steps atomic, explain changes
