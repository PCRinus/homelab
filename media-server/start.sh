#!/bin/bash
# Media Server Stack startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"
source "${SCRIPT_DIR}/../scripts/lib/host-readiness.sh"

echo "🎬 Starting Media Server Stack..."

if [ -z "${MEDIA_PATH:-}" ] || ! homelab_recover_media_mount "$MEDIA_PATH"; then
    echo "❌ Refusing to start media services without a real NAS mount" >&2
    exit 1
fi

cd "${SCRIPT_DIR}"

# --- Pull and Start Containers ---
echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
# Recreate only services that bind the NAS. This prevents an existing container
# from retaining the empty underlying directory after the automount recovers.
homelab_compose up -d --force-recreate \
    qbittorrent sonarr sonarr-anime radarr plex bazarr checkrr
homelab_compose up -d

echo "✅ Media Server Stack started!"
