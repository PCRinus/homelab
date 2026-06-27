# VPS Stack

This directory versions the services running on the public VPS used by Pangolin for Plex remote access.

## Services

- `pangolin`: Pangolin control plane, using the existing config under `/opt/pangolin/config`.
- `gerbil`: Pangolin WireGuard/data-plane service, exposing ports `80`, `443`, `51820/udp`, and `21820/udp`.
- `traefik`: Reverse proxy used by Pangolin, sharing Gerbil's network namespace.
- `tailscale`: Tailscale node for private access to VPS-only services.
- `dozzle-agent`: Remote Dozzle agent for VPS container logs.

The Pangolin config, keys, Traefik config, Let's Encrypt data, and generated state are intentionally not committed. They remain on the VPS under `/opt/pangolin/config`.

## First-Time VPS Setup

The VPS already has Docker, Docker Compose, and the existing Pangolin runtime under `/opt/pangolin`.

Create a local runtime env file on the VPS when host-specific overrides are needed:

```bash
cd /opt/homelab/vps
cp .env.example .env
```

The deploy workflow authenticates Tailscale on first run with `TS_VPS_AUTHKEY`. The Tailscale container uses host networking so the VPS gets its own tailnet IP, and persists state in `/opt/homelab/vps/tailscale-state`.

The start script auto-detects the VPS Tailscale IPv4 address and binds the Dozzle agent to it. You can override that manually in `/opt/homelab/vps/.env`:

```env
DOZZLE_AGENT_BIND=<vps-tailscale-ipv4>
```

Do not bind the Dozzle agent to `0.0.0.0` unless the port is otherwise restricted; the agent can read Docker logs and container metadata from the VPS Docker socket.

## Deploying

Manual deployment from the VPS:

```bash
cd /opt/homelab/vps
./start.sh
```

GitHub Actions deployment uses `.github/workflows/deploy-vps.yml` and SSHs directly to the VPS. It syncs this `vps/` directory to the VPS and then runs `start.sh`; it does not require GitHub credentials on the VPS.

Configure these repository settings:

- Secret `VPS_SSH_PRIVATE_KEY`: private SSH key accepted by `root@194.102.107.75`.
- Secret `TS_VPS_AUTHKEY`: non-ephemeral, pre-approved Tailscale auth key used for first-run VPS enrollment.
- Optional variable `TS_VPS_EXTRA_ARGS`: extra `tailscale up` args, for example `--advertise-tags=tag:vps` if the auth key is not already tagged.
- Variable `VPS_SSH_HOST`: `194.102.107.75`.
- Variable `VPS_SSH_USER`: `root`.
- Variable `VPS_REPO_DIR`: `/opt/homelab`.

The workflow preserves `/opt/homelab/vps/.env` and `/opt/homelab/vps/tailscale-state/` on the VPS so host-local runtime settings and the Tailscale node identity are not removed by deploys.

## Dozzle Integration

The home-server Dozzle UI reads remote agents from `DOZZLE_REMOTE_AGENT` in the encrypted repo env.

After the VPS Dozzle agent is reachable on a private address, set:

```env
DOZZLE_REMOTE_AGENT=<vps-tailscale-ipv4>:7007|homeserver-vps|VPS
```

Then deploy the monitoring stack so the home-server Dozzle container restarts with the new remote agent.

## Updating Pangolin

Update image tags in `vps/compose.yml`, commit the change, and push to `main`. The VPS deploy workflow will pull the new image and recreate the affected containers.
