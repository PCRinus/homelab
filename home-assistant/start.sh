#!/bin/bash
# Home Assistant startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"

echo "🏠 Starting Home Assistant..."

cd "${SCRIPT_DIR}"

# Check if secrets file exists
if [ ! -f "secrets.yaml" ]; then
    echo "⚠️  secrets.yaml not found — copy from secrets.yaml.example and fill in values"
fi

echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
homelab_compose up -d

echo "✅ Home Assistant started!"
