#!/bin/bash
# Minecraft Servers startup script
# Starts all server-specific compose files (skips common.compose.yml)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🎮 Starting Minecraft Servers..."

cd "${SCRIPT_DIR}"

STARTED=0
for f in *.compose.yml; do
    [[ "$f" == "common.compose.yml" ]] && continue
    SERVER_NAME="${f%.compose.yml}"
    echo "📦 Pulling ${SERVER_NAME}..."
    docker compose -f "$f" pull
    echo "🚀 Starting ${SERVER_NAME}..."
    docker compose -f "$f" up -d
    STARTED=$((STARTED + 1))
done

if [ "$STARTED" -eq 0 ]; then
    echo "⚠️  No server compose files found"
else
    echo "✅ ${STARTED} Minecraft server(s) started!"
fi
