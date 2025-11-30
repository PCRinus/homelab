#!/bin/bash
# Media Server Stack startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎬 Starting Media Server Stack..."

cd "${SCRIPT_DIR}"

# --- Pull and Start Containers ---
echo "📦 Pulling latest images..."
docker compose pull

echo "🚀 Starting containers..."
docker compose up -d

echo "✅ Media Server Stack started!"
