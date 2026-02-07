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

# If DOCKER_SOCK is set but DOCKER_HOST isn't, export DOCKER_HOST so the
# docker CLI uses the correct socket (important for rootless Docker).
if [ -n "$DOCKER_SOCK" ] && [ -z "$DOCKER_HOST" ]; then
    export DOCKER_HOST="unix://${DOCKER_SOCK}"
fi

if ! docker info > /dev/null 2>&1; then
    # Determine which socket we're trying to use
    SOCK="${DOCKER_SOCK:-/var/run/docker.sock}"

    if [ ! -S "$SOCK" ]; then
        echo -e "${RED}Docker socket not found at ${SOCK}${NC}"
        echo -e "Is Docker installed and running?"
        echo -e "  Check with: ${YELLOW}systemctl --user status docker${NC}  (rootless)"
        echo -e "         or:  ${YELLOW}sudo systemctl status docker${NC}   (root mode)"
    elif [ ! -r "$SOCK" ] || [ ! -w "$SOCK" ]; then
        echo -e "${RED}Docker is running but your user cannot access the socket at ${SOCK}${NC}"
        echo -e "Fix with one of:"
        echo -e "  ${YELLOW}sudo usermod -aG docker \$USER${NC}  then log out and back in"
        echo -e "  or set up rootless Docker: ${YELLOW}dockerd-rootless-setuptool.sh install${NC}"
    else
        echo -e "${RED}Docker is not responding (socket exists at ${SOCK} but 'docker info' failed)${NC}"
        echo -e "  Try: ${YELLOW}sudo systemctl restart docker${NC}"
    fi
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
