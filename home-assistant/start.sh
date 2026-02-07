#!/bin/bash
# Home Assistant startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🏠 Starting Home Assistant..."

cd "${SCRIPT_DIR}"

# Check if secrets file exists
if [ ! -f "secrets.yaml" ]; then
    echo "⚠️  secrets.yaml not found — copy from secrets.yaml.example and fill in values"
fi

echo "📦 Pulling latest images..."
docker compose pull

echo "🚀 Starting containers..."
docker compose up -d

echo "✅ Home Assistant started!"
