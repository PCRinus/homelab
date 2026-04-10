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
source "${SCRIPT_DIR}/lib/compose-env.sh"

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
if [ -z "$DOCKER_DATA" ] || [ -z "$MEDIA_PATH" ] || [ -z "${QBITTORRENT_INCOMPLETE_PATH:-}" ] || [ -z "$DOCKER_SOCK" ]; then
    echo -e "${RED}Environment variables not set (DOCKER_DATA, MEDIA_PATH, QBITTORRENT_INCOMPLETE_PATH, DOCKER_SOCK)${NC}"
    echo -e "Run ${YELLOW}./scripts/init.sh${NC} first, then ${YELLOW}source ~/.zshenv${NC}"
    exit 1
fi

# --- Check runtime secrets source exists ---
if [ ! -f "${REPO_DIR}/.env" ] && [ ! -f "${REPO_DIR}/.env.enc" ]; then
    echo -e "${RED}Neither .env nor .env.enc was found${NC}"
    echo -e "Run ${YELLOW}./scripts/init.sh${NC} first"
    exit 1
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

# --- Check NAS mount ---
if [ -n "$MEDIA_PATH" ]; then
    if [ ! -d "$MEDIA_PATH" ]; then
        echo -e "${YELLOW}WARNING: Media path ${MEDIA_PATH} does not exist${NC}"
        echo -e "Services mounting this path (media-server, homepage) will fail."
        echo -e "Set up the NAS mount first: ${YELLOW}./scripts/setup-nas-mount.sh${NC}"
        echo
    else
        # With x-systemd.automount, the mount point exists but the NFS share
        # only connects on first access. Docker bind-mounts don't trigger
        # automount, so we need to access the path to wake it up.
        if ! mountpoint -q "$MEDIA_PATH" 2>/dev/null; then
            echo -e "${YELLOW}Activating NAS mount at ${MEDIA_PATH}...${NC}"
            if timeout 10 ls "$MEDIA_PATH" > /dev/null 2>&1 && mountpoint -q "$MEDIA_PATH" 2>/dev/null; then
                echo -e "${GREEN}NAS mount active${NC}"
            else
                echo -e "${RED}WARNING: ${MEDIA_PATH} is not a mount point${NC}"
                echo -e "Services mounting this path (media-server, homepage) will fail."
                echo -e "Check NAS connectivity: ${YELLOW}sudo mount ${MEDIA_PATH}${NC}"
                echo
            fi
        fi
    fi
fi

# --- Check local qBittorrent staging path ---
if [ ! -d "$QBITTORRENT_INCOMPLETE_PATH" ]; then
    echo -e "${YELLOW}Creating qBittorrent incomplete path at ${QBITTORRENT_INCOMPLETE_PATH}${NC}"
    mkdir -p "$QBITTORRENT_INCOMPLETE_PATH"
fi

if [[ "$QBITTORRENT_INCOMPLETE_PATH" == "$MEDIA_PATH" || "$QBITTORRENT_INCOMPLETE_PATH" == "$MEDIA_PATH/"* ]]; then
    echo -e "${YELLOW}WARNING: QBITTORRENT_INCOMPLETE_PATH is inside MEDIA_PATH${NC}"
    echo -e "Active torrent writes will still hit the NAS."
else
    FS_TYPE=$(stat -f -c '%T' "$QBITTORRENT_INCOMPLETE_PATH" 2>/dev/null || true)
    case "$FS_TYPE" in
        nfs|nfs4|cifs|smb2|smb3|fuseblk)
            echo -e "${YELLOW}WARNING: QBITTORRENT_INCOMPLETE_PATH is on a network filesystem (${FS_TYPE})${NC}"
            echo -e "Use a local path to avoid qBittorrent I/O errors during NAS stalls."
            ;;
    esac
fi

# --- Start stacks in order ---
# Media server first (creates the media-net network via compose)
# Then services that depend on media-net
STACKS=(
    "media-server"
    "adguard"
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
        # cloudflare-tunnel depends on networks from other stacks — verify they exist
        if [[ "$stack" == "cloudflare-tunnel" ]]; then
            MISSING_NETS=()
            for net in monitoring_default media-net; do
                if ! docker network inspect "$net" > /dev/null 2>&1; then
                    MISSING_NETS+=("$net")
                fi
            done
            if [ ${#MISSING_NETS[@]} -gt 0 ]; then
                echo -e "${BOLD}━━━ ${stack} ━━━${NC}"
                echo -e "${RED}Skipping ${stack} — missing external networks: ${MISSING_NETS[*]}${NC}"
                echo -e "Fix the failed stacks above first, then re-run."
                FAILED+=("$stack")
                echo
                continue
            fi
        fi
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
        homelab_compose -f "$f" pull
        homelab_compose -f "$f" up -d
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
