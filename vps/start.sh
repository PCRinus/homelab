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

echo "Starting containers..."
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml up -d --remove-orphans

echo "Container status:"
docker compose "${COMPOSE_ENV_ARGS[@]}" -f compose.yml ps

echo "VPS stack started."
