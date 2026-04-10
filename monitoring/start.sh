#!/bin/bash
# Monitoring Stack startup script (Dozzle + Gatus)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"

echo "📈 Starting Monitoring Stack..."

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
homelab_compose up -d

# Gatus reads config.yaml only at startup, but docker compose up -d won't
# restart it if only the bind-mounted config file changed. Force a restart
# so Gatus always picks up the latest config.
echo "🔄 Restarting Gatus to pick up config changes..."
homelab_compose restart gatus

echo "✅ Monitoring Stack started!"
