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

echo "✅ Monitoring Stack started!"
