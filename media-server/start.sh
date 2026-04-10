#!/bin/bash
# Media Server Stack startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"

echo "🎬 Starting Media Server Stack..."

cd "${SCRIPT_DIR}"

# --- Pull and Start Containers ---
echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
homelab_compose up -d

echo "✅ Media Server Stack started!"
