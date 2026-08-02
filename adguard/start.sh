#!/bin/bash
# AdGuard Home startup script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/lib/compose-env.sh"
source "${SCRIPT_DIR}/../scripts/lib/host-readiness.sh"

ADGUARD_LAN_IP="${ADGUARD_LAN_IP:-192.168.1.166}"
export ADGUARD_LAN_IP

echo "🛡️ Starting AdGuard Home..."

echo "🌐 Waiting for LAN address ${ADGUARD_LAN_IP}..."
homelab_wait_for_ipv4 "$ADGUARD_LAN_IP"

cd "${SCRIPT_DIR}"

echo "📦 Pulling latest images..."
homelab_compose pull

echo "🚀 Starting containers..."
homelab_compose up -d --force-recreate

echo "✅ AdGuard Home started!"
