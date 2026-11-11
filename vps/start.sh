#!/bin/bash
# VPS stack startup script (Pangolin + Dozzle agent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE_ENV_ARGS=()
if [ -f ".env" ]; then
    COMPOSE_ENV_ARGS=(--env-file .env)
fi

# VPS_BOOT=1 is set by homelab-vps.service. At boot (or after a Docker restart)
# Docker races every container up at once, and the ones publishing ports on the
# Tailscale IP fail with "cannot assign requested address" and are never retried.
# Boot mode re-runs compose once Tailscale is up, skips the registry pull, and
# fails instead of falling back to 127.0.0.1 so systemd retries.
VPS_BOOT="${VPS_BOOT:-0}"

echo "Starting VPS stack..."

if [ "${VPS_BOOT}" = "1" ]; then
    echo "Boot mode: skipping image pull"
else
    echo "Pulling latest images..."
    docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml pull
fi

echo "Starting Tailscale..."
mkdir -p "${TAILSCALE_STATE_DIR:-./tailscale-state}"
TAILSCALE_UP_ARGS=(up -d)
if [ -n "${TS_AUTHKEY:-}" ]; then
    TAILSCALE_UP_ARGS+=(--force-recreate)
elif docker inspect tailscale > /dev/null 2>&1; then
    if docker inspect tailscale --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q '^TS_AUTHKEY=.\+'; then
        TAILSCALE_UP_ARGS+=(--force-recreate)
        echo "Recreating Tailscale container without first-run auth key"
    fi
fi
TAILSCALE_UP_ARGS+=(tailscale)
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml "${TAILSCALE_UP_ARGS[@]}"

if [ "${DOZZLE_AGENT_BIND:-}" = "" ] || [ "${DOZZLE_AGENT_BIND:-}" = "127.0.0.1" ]; then
    TAILSCALE_IP=""
    for _ in {1..30}; do
        TAILSCALE_IP="$(docker exec tailscale tailscale ip -4 2>/dev/null | head -n1 || true)"
        if [ -n "${TAILSCALE_IP}" ]; then
            break
        fi
        sleep 1
    done

    if [ -n "${TAILSCALE_IP}" ]; then
        export DOZZLE_AGENT_BIND="${TAILSCALE_IP}"
        echo "Binding Dozzle agent to Tailscale IP ${DOZZLE_AGENT_BIND}"
    elif [ "${VPS_BOOT}" = "1" ]; then
        echo "Tailscale IP not available yet; failing so systemd retries"
        exit 1
    else
        export DOZZLE_AGENT_BIND="127.0.0.1"
        echo "Tailscale IP not available yet; binding Dozzle agent to 127.0.0.1"
    fi
fi

# Note: .env is only passed to compose, never sourced here, so DOZZLE_AGENT_BIND
# above comes from the shell environment and the detected IP overrides .env.
# Whatever address we bind to must be on a host interface before Docker can
# publish ports on it, so wait for it regardless of where it came from.
if [ "${DOZZLE_AGENT_BIND}" != "127.0.0.1" ]; then
    for _ in {1..30}; do
        if ip -4 -o addr show | grep -F " ${DOZZLE_AGENT_BIND}/" > /dev/null; then
            break
        fi
        sleep 1
    done
fi

echo "Starting containers..."
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml up -d --remove-orphans

# When Docker restores these at boot before the Tailscale IP exists, the bind
# fails and Docker drops the container's network attachment. A later start
# (including compose up) brings it up with only loopback and no published port,
# and compose considers it healthy. Recreate any that ended up without a port.
TS_BOUND_SERVICES=(dozzle-agent memory-monitor)
RECREATE=()
for svc in "${TS_BOUND_SERVICES[@]}"; do
    cid="$(docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml ps -q "${svc}")"
    if [ -z "${cid}" ] || [ -z "$(docker port "${cid}" 2>/dev/null)" ]; then
        RECREATE+=("${svc}")
    fi
done
if [ "${#RECREATE[@]}" -gt 0 ]; then
    echo "Recreating services without published ports: ${RECREATE[*]}"
    docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml up -d --force-recreate --no-deps "${RECREATE[@]}"
fi

echo "Container status:"
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml ps

echo "VPS stack started."
