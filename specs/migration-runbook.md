# Homelab Migration Runbook

This repo intentionally does not ship an automated migration script anymore.
The previous script had drifted away from the current stack layout, secret-loading model, and Minecraft orchestration.

The migration strategy for this homelab is:

1. Treat the repo as the control plane.
2. Treat `${DOCKER_DATA}` and other bind-mounted host paths as the data plane.
3. Move data with backups or `rsync`, then bring stacks up gradually.

## What Is Actually Portable

Most state in this homelab is already portable because services persist to bind-mounted host paths instead of opaque Docker named volumes.

Primary migration targets:

- `${DOCKER_DATA}` for app configs, databases, caches, and metadata
- `${MEDIA_PATH}` and any NAS mounts
- Encrypted repo secrets plus your Age private key
- `cloudflare-tunnel/tunnel-token.enc` and `media-server/wg0.conf.enc`

Less portable host-specific concerns:

- Docker socket path and permissions
- GPU device access and render group configuration
- NAS mount configuration
- Home Assistant integrations tied to hardware or local network topology
- External DNS, tunnel, and router cutover

## Recommended Approaches

### Option 1: Backup and Restore

Preferred when you already have reliable backups or want the cleanest recovery story.

Use this when:

- Moving to a new machine with time to validate before cutover
- Rebuilding after host failure
- You want migration and disaster recovery to use the same process

Recommended backup scope:

- `${DOCKER_DATA}`
- Repo checkout
- Age key at `~/.config/sops/age/keys.txt`
- NAS mount configuration

Good tooling choices:

- Filesystem snapshots if available
- `restic` or similar backup tooling for `${DOCKER_DATA}`
- Existing ad hoc stack backups for Seerr and Pulsarr are additive, not complete host migration coverage

### Option 2: `rsync` Cutover

Preferred for a deliberate host-to-host migration when both machines are available.

Use this when:

- You can temporarily stop services on the old host
- You want direct transfer instead of backup restore

Typical command shape:

```bash
rsync -aHAX --numeric-ids --delete --info=progress2 old-host:/home/mircea/docker/ /home/mircea/docker/
```

Notes:

- Stop write-heavy stacks before the final sync
- Run an initial warm sync while services are still live if the dataset is large
- Run a final sync after stopping the source stacks for consistency

## Migration Checklist

### 1. Prepare the New Host

- Install Docker and Docker Compose
- Clone the repo
- Restore your Age key to `~/.config/sops/age/keys.txt`
- Run `./scripts/init.sh`
- Load `~/.zshenv`
- Create required Docker networks such as `media-net`
- Verify NAS mounts and local staging paths

### 2. Restore Secrets and Local Files

- Ensure `.env.enc` is present in the repo
- Verify `scripts/secrets.sh status`
- Restore or verify encrypted files for Cloudflare and WireGuard
- Do not rely on plaintext `.env` as the source of truth; runtime now prefers `.env.enc`

### 3. Move Application Data

- Restore or `rsync` `${DOCKER_DATA}`
- Verify ownership and permissions
- Verify path-dependent mounts still match the new host layout

### 4. Start Core Stacks Gradually

Suggested order:

1. `media-server`
2. `monitoring`
3. `homepage`
4. `home-assistant`
5. `adguard`
6. `cloudflare-tunnel`
7. `minecraft-servers`

Use per-stack starts first instead of one large cutover.

### 5. Verify Health

- `docker ps`
- Gatus and Dozzle availability
- Plex playback and hardware transcoding
- qBittorrent VPN connectivity
- Sonarr, Radarr, and Prowlarr API connectivity
- Home Assistant startup and integration health
- Homepage widgets and Docker access
- Cloudflare tunnel connectivity

### 6. Cut Over External Traffic

- Update DNS or tunnel routing if required
- Verify public access paths
- Decommission the old host only after stable validation

## Stack-Specific Notes

### Media Server

- Large Plex metadata trees can take time to copy
- qBittorrent, Sonarr, Radarr, Prowlarr, and Bazarr state all live under `${DOCKER_DATA}`
- Preserve the incomplete download path if you want qBittorrent to resume cleanly

### Home Assistant

- Expect some integrations to need revalidation if hostnames, IPs, or hardware bindings change
- Validate automations, devices, and trusted proxy settings after startup

### Cloudflare Tunnel

- The tunnel token is portable, but validate host reachability and watchdog behavior after cutover

### Minecraft

- World data is portable through `${DOCKER_DATA}`
- Keep server compose files, shared config, and generated mod metadata in sync with the repo

## When To Avoid Automation

Avoid reviving a one-shot migration script unless you are actively rehearsing it.
For a homelab that migrates once every few years, a maintained runbook plus backup/restore is safer than stale automation.