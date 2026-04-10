#!/bin/bash
# AdGuard Home startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"

echo "🛡️ Starting AdGuard Home..."

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
homelab_compose up -d

echo "✅ AdGuard Home started!"
