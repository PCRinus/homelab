#!/bin/bash
# Cloudflared deployment script for tunnel management

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if required files exist
if [ ! -f "tunnel-token" ]; then
    echo "Error: tunnel-token file not found!"
    echo "Create it with: echo 'YOUR_TUNNEL_TOKEN' > tunnel-token"
    exit 1
fi

# Verify file is readable
if [ ! -r "tunnel-token" ]; then
    echo "Error: tunnel-token is not readable!"
    exit 1
fi

echo "✓ Tunnel token file found and readable"

# Stop any existing container
echo "Stopping existing container (if any)..."
docker compose down 2>/dev/null || true

# Remove any orphaned volumes
echo "Cleaning up..."
docker volume prune -f 2>/dev/null || true

# Start the container
echo "Starting cloudflared container..."
docker compose up -d

# Wait a moment for the container to start
sleep 3

# Check container status
echo ""
echo "Container status:"
docker ps --filter "name=cloudflared" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Show recent logs
echo ""
echo "Recent logs:"
docker logs cloudflared --tail 10

echo ""
echo "✓ Cloudflared started successfully!"