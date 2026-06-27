# VPS Stack

This directory versions the services running on the public VPS used by Pangolin for Plex remote access.

## Services

- `pangolin`: Pangolin control plane, using the existing config under `/opt/pangolin/config`.
- `gerbil`: Pangolin WireGuard/data-plane service, exposing ports `80`, `443`, `51820/udp`, and `21820/udp`.
- `traefik`: Reverse proxy used by Pangolin, sharing Gerbil's network namespace.
- `dozzle-agent`: Remote Dozzle agent for VPS container logs.

The Pangolin config, keys, Traefik config, Let's Encrypt data, and generated state are intentionally not committed. They remain on the VPS under `/opt/pangolin/config`.

## First-Time VPS Setup

The VPS already has Docker, Docker Compose, and the existing Pangolin runtime under `/opt/pangolin`.

Create a local runtime env file on the VPS when needed:

```bash
cd /opt/homelab/vps
cp .env.example .env
```

Keep `DOZZLE_AGENT_BIND=127.0.0.1` until a private transport is ready. The preferred setup is to install Tailscale on the VPS, then set:

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
- Variable `VPS_SSH_HOST`: `194.102.107.75`.
- Variable `VPS_SSH_USER`: `root`.
- Variable `VPS_REPO_DIR`: `/opt/homelab`.

The workflow preserves `/opt/homelab/vps/.env` on the VPS so host-local runtime settings such as `DOZZLE_AGENT_BIND` are not removed by deploys.

## Dozzle Integration

The home-server Dozzle UI reads remote agents from `DOZZLE_REMOTE_AGENT` in the encrypted repo env.

After the VPS Dozzle agent is reachable on a private address, set:

```env
DOZZLE_REMOTE_AGENT=<vps-tailscale-ipv4>:7007|homeserver-vps|VPS
```

Then deploy the monitoring stack so the home-server Dozzle container restarts with the new remote agent.

## Updating Pangolin

Update image tags in `vps/compose.yml`, commit the change, and push to `main`. The VPS deploy workflow will pull the new image and recreate the affected containers.
