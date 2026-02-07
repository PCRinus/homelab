#!/bin/bash
# Homepage Dashboard startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "📊 Starting Homepage Dashboard..."

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
docker compose pull

echo "🚀 Starting containers..."
docker compose up -d

echo "✅ Homepage Dashboard started!"
