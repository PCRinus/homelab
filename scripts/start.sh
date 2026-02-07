#!/bin/bash
# ===========================================
# Start all homelab services
# ===========================================
# Starts all core stacks in dependency order.
# Minecraft servers are optional and skipped by default.
#
# Usage:
#   ./scripts/start.sh              # Start core services only
#   ./scripts/start.sh --all        # Include Minecraft servers
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

# --- Preflight checks ---
if [ -z "$DOCKER_DATA" ] || [ -z "$MEDIA_PATH" ] || [ -z "$DOCKER_SOCK" ]; then
    echo -e "${RED}Environment variables not set (DOCKER_DATA, MEDIA_PATH, DOCKER_SOCK)${NC}"
    echo -e "Run ${YELLOW}./scripts/init.sh${NC} first, then ${YELLOW}source ~/.zshenv${NC}"
    exit 1
fi

# --- Check secrets are decrypted ---
if [ ! -f "${REPO_DIR}/.env" ]; then
    # Check if encrypted version exists
    if [ -f "${REPO_DIR}/.env.enc" ]; then
        echo -e "${RED}Secrets not decrypted — .env.enc exists but .env does not${NC}"
        echo -e "Run ${YELLOW}./scripts/secrets.sh decrypt${NC} first"
        exit 1
    else
        echo -e "${RED}.env file not found${NC}"
        echo -e "Run ${YELLOW}./scripts/init.sh${NC} first"
        exit 1
    fi
fi

if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Docker is not running or not accessible${NC}"
    exit 1
fi

# Create media-net if it doesn't exist
if ! docker network inspect media-net > /dev/null 2>&1; then
    echo -e "${YELLOW}Creating media-net network...${NC}"
    docker network create media-net
fi

# --- Start stacks in order ---
# Media server first (creates the media-net network definition)
# Then services that depend on media-net
STACKS=(
    "media-server"
    "monitoring"
    "homepage"
    "home-assistant"
    "cloudflare-tunnel"
)

echo -e "${BOLD}Starting homelab services...${NC}"
echo

FAILED=()

for stack in "${STACKS[@]}"; do
    script="${REPO_DIR}/${stack}/start.sh"
    if [ -x "$script" ]; then
        echo -e "${BOLD}━━━ ${stack} ━━━${NC}"
        if "$script"; then
            echo
        else
            echo -e "${RED}Failed to start ${stack}${NC}"
            FAILED+=("$stack")
            echo
        fi
    else
        echo -e "${YELLOW}Skipping ${stack} — no start.sh found${NC}"
    fi
done

# --- Optional: Minecraft servers ---
if $INCLUDE_MINECRAFT; then
    echo -e "${BOLD}━━━ minecraft-servers ━━━${NC}"
    MC_DIR="${REPO_DIR}/minecraft-servers"
    cd "$MC_DIR"
    for f in *.compose.yml; do
        [[ "$f" == "common.compose.yml" ]] && continue
        echo "Starting ${f}..."
        docker compose -f "$f" pull
        docker compose -f "$f" up -d
    done
    echo -e "✅ Minecraft servers started!"
    echo
else
    echo -e "${YELLOW}Skipping Minecraft servers (use --all to include)${NC}"
fi

# --- Summary ---
echo
if [ ${#FAILED[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All services started successfully!${NC}"
else
    echo -e "${RED}${BOLD}Some stacks failed: ${FAILED[*]}${NC}"
    exit 1
fi
