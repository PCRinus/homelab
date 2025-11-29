# Copilot Instructions for Homelab Repository

## Project Context
- This is a homelab infrastructure repository managing self-hosted services via Docker Compose
- Services run on a Linux server with Docker in rootless mode
- Storage is mounted from a NAS at `/mnt/unas/media/`

## Docker Compose Guidelines
- Use Docker Compose v2 syntax (no `version:` field needed)
- Always include `restart: unless-stopped` for production services
- Use environment variables or secrets files for sensitive data (never commit secrets)
- Prefer `linuxserver.io` images when available for consistent PUID/PGID handling
- Include health checks where the image supports them
- Use named volumes for persistent data, bind mounts for config files

## File Conventions
- Compose files: `compose.yml` (not `docker-compose.yml`)
- Secrets: `secrets.yaml` with `.example` template committed
- Documentation: `README.md` per service directory

## YAML Style
- 2-space indentation
- Use lowercase for keys
- Add comments for non-obvious port mappings or volume mounts
- Group related environment variables together

## Infrastructure Notes
- Cloudflare Tunnel is used for external access (no exposed ports needed)
- Terraform manages Cloudflare DNS and R2 storage
- Homepage dashboard aggregates all services
- Media stack: Sonarr, Prowlarr, Transmission with Buildarr for config management

## When Suggesting Changes
- Consider rootless Docker limitations (no privileged mode, limited port binding)
- Check for existing patterns in similar services before suggesting new approaches
- Preserve existing secrets/environment variable patterns

## Workflow Preferences
- For multi-step tasks, present a clear numbered plan before making changes
- Keep each step atomic and committable—one logical change per step
- Pause after presenting the plan so the user can review, adjust, or approve
- When making edits, explain what changed and why
- If a step fails or needs adjustment, re-evaluate the plan before continuing
