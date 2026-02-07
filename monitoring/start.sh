#!/bin/bash
# Monitoring Stack startup script (Dozzle + Gatus)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📈 Starting Monitoring Stack..."

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
docker compose pull

echo "🚀 Starting containers..."
docker compose up -d

echo "✅ Monitoring Stack started!"
