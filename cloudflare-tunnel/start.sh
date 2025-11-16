#!/bin/bash
# Cloudflared startup script to prevent directory mount issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if required files exist
if [ ! -f "config.yml" ]; then
    echo "Error: config.yml not found!"
    exit 1
fi

if [ ! -f "2a32c37d-447c-4d24-9256-9deb86bc686f.json" ]; then
    echo "Error: Tunnel credentials JSON file not found!"
    exit 1
fi

# Verify files are readable
if [ ! -r "config.yml" ]; then
    echo "Error: config.yml is not readable!"
    exit 1
fi

if [ ! -r "2a32c37d-447c-4d24-9256-9deb86bc686f.json" ]; then
    echo "Error: Tunnel credentials JSON file is not readable!"
    exit 1
fi

echo "✓ All required files found and readable"

# Stop any existing container
echo "Stopping existing container (if any)..."
sudo docker compose down 2>/dev/null || true

# Remove any orphaned volumes/directories that Docker might have created
echo "Cleaning up..."
sudo docker volume prune -f 2>/dev/null || true

# Start the container
echo "Starting cloudflared container..."
sudo docker compose up -d

# Wait a moment for the container to start
sleep 3

# Check container status
echo ""
echo "Container status:"
sudo docker ps --filter "name=cloudflared" --format "table {{.Names}}\t{{.Status}}\t{{.State}}"

# Show recent logs
echo ""
echo "Recent logs:"
sudo docker logs cloudflared --tail 10

echo ""
echo "✓ Cloudflared started successfully!"
