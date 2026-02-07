#!/bin/bash
# ===========================================
# Stop all homelab services
# ===========================================
# Stops all core stacks in reverse dependency order.
# Minecraft servers are included only with --all.
# Networks created by compose are removed with the stacks.
#
# Usage:
#   ./scripts/stop.sh              # Stop core services only
#   ./scripts/stop.sh --all        # Include Minecraft servers
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

INCLUDE_MINECRAFT=false
if [[ "$1" == "--all" ]]; then
    INCLUDE_MINECRAFT=true
fi

if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Docker is not running or not accessible${NC}"
    exit 1
fi

echo -e "${BOLD}Stopping homelab services...${NC}"
echo

# --- Stop stacks in reverse dependency order ---
# cloudflare-tunnel first (depends on all other networks)
# media-server last (owns media-net)
STACKS=(
    "cloudflare-tunnel"
    "home-assistant"
    "homepage"
    "monitoring"
    "media-server"
)

FAILED=()

# --- Optional: Minecraft servers ---
if $INCLUDE_MINECRAFT; then
    echo -e "${BOLD}━━━ minecraft-servers ━━━${NC}"
    MC_DIR="${REPO_DIR}/minecraft-servers"
    if [ -d "$MC_DIR" ]; then
        cd "$MC_DIR"
        for f in *.compose.yml; do
            [[ "$f" == "common.compose.yml" ]] && continue
            if [ -f "$f" ]; then
                echo "Stopping ${f}..."
                docker compose -f "$f" down
            fi
        done
        echo -e "✅ Minecraft servers stopped!"
    else
        echo -e "${YELLOW}minecraft-servers directory not found${NC}"
    fi
    echo
else
    echo -e "${YELLOW}Skipping Minecraft servers (use --all to include)${NC}"
fi

for stack in "${STACKS[@]}"; do
    compose_file="${REPO_DIR}/${stack}/compose.yml"
    if [ -f "$compose_file" ]; then
        echo -e "${BOLD}━━━ ${stack} ━━━${NC}"
        if (cd "${REPO_DIR}/${stack}" && docker compose down); then
            echo
        else
            echo -e "${RED}Failed to stop ${stack}${NC}"
            FAILED+=("$stack")
            echo
        fi
    else
        echo -e "${YELLOW}Skipping ${stack} — no compose.yml found${NC}"
    fi
done

# --- Remove media-net if it's still lingering ---
if docker network inspect media-net > /dev/null 2>&1; then
    echo -e "${YELLOW}Removing media-net network...${NC}"
    docker network rm media-net 2>/dev/null || echo -e "${YELLOW}Could not remove media-net (may still have connected containers)${NC}"
fi

# --- Summary ---
echo
if [ ${#FAILED[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All services stopped!${NC}"
else
    echo -e "${RED}${BOLD}Some stacks failed to stop: ${FAILED[*]}${NC}"
    exit 1
fi
