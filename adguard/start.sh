#!/bin/bash
# AdGuard Home startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🛡️ Starting AdGuard Home..."

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
docker compose pull

echo "🚀 Starting containers..."
docker compose up -d

echo "✅ AdGuard Home started!"
