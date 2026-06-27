#!/bin/bash
# VPS stack startup script (Pangolin + Dozzle agent)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

COMPOSE_ENV_ARGS=()
if [ -f ".env" ]; then
    COMPOSE_ENV_ARGS=(--env-file .env)
fi

echo "Starting VPS stack..."

echo "Pulling latest images..."
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml pull

echo "Starting Tailscale..."
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml up -d tailscale

if [ "${DOZZLE_AGENT_BIND:-}" = "" ] || [ "${DOZZLE_AGENT_BIND:-}" = "127.0.0.1" ]; then
    TAILSCALE_IP="$(docker exec tailscale tailscale ip -4 2>/dev/null | head -n1 || true)"
    if [ -n "${TAILSCALE_IP}" ]; then
        export DOZZLE_AGENT_BIND="${TAILSCALE_IP}"
        echo "Binding Dozzle agent to Tailscale IP ${DOZZLE_AGENT_BIND}"
    else
        export DOZZLE_AGENT_BIND="127.0.0.1"
        echo "Tailscale IP not available yet; binding Dozzle agent to 127.0.0.1"
    fi
fi

echo "Starting containers..."
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml up -d --remove-orphans

echo "Container status:"
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml ps

echo "VPS stack started."
