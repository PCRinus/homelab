#!/bin/bash
# Media Server Stack startup script
# Prepares configuration and starts all containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASE="/home/mircea/docker"

echo "🎬 Starting Media Server Stack..."

# --- Transmission Setup ---
echo "📋 Copying Transmission settings..."
TRANSMISSION_CONFIG="${CONFIG_BASE}/transmission"
cp "${SCRIPT_DIR}/transmission/settings.json" "${TRANSMISSION_CONFIG}/settings.json"

# --- Pull and Start Containers ---
echo "📦 Pulling latest images..."
cd "${SCRIPT_DIR}"
docker compose pull

echo "🚀 Starting containers..."
docker compose up -d

echo "✅ Media Server Stack started!"
