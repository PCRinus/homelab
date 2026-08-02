#!/bin/bash
# Homepage Dashboard startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"
source "${SCRIPT_DIR}/../scripts/lib/host-readiness.sh"

echo "📊 Starting Homepage Dashboard..."

if [ -z "${MEDIA_PATH:-}" ] || ! homelab_recover_media_mount "$MEDIA_PATH"; then
    echo "❌ Refusing to start Homepage without a real NAS mount" >&2
    exit 1
fi

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
homelab_compose up -d --force-recreate

echo "✅ Homepage Dashboard started!"
