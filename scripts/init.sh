#!/bin/bash
# ===========================================
# Homelab Environment Setup
# ===========================================
# Run this on a fresh server after cloning the repo.
# Sets up path variables in ~/.zshenv so Docker Compose
# can resolve them in compose files.
#
# Usage: ./scripts/init.sh
# ===========================================

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ZSHENV="$HOME/.zshenv"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MARKER_START="# --- Homelab paths (managed by init.sh) ---"
MARKER_END="# --- End homelab paths ---"

echo -e "${BLUE}${BOLD}========================================${NC}"
echo -e "${BLUE}${BOLD}  Homelab Environment Setup${NC}"
echo -e "${BLUE}${BOLD}========================================${NC}"
echo

# ===========================================
# 1. DOCKER_DATA - Container persistent data
# ===========================================
DEFAULT_DOCKER_DATA="$HOME/docker"
echo -e "${BOLD}Container data directory${NC}"
echo "Where persistent container data (configs, databases, cache) is stored."
echo "Each service gets a subdirectory (e.g., sonarr/, plex/, etc.)"
echo -e "Default: ${GREEN}${DEFAULT_DOCKER_DATA}${NC}"
read -rp "> Path [${DEFAULT_DOCKER_DATA}]: " INPUT_DOCKER_DATA
DOCKER_DATA="${INPUT_DOCKER_DATA:-$DEFAULT_DOCKER_DATA}"

if [ ! -d "$DOCKER_DATA" ]; then
    echo -e "${YELLOW}Directory does not exist: ${DOCKER_DATA}${NC}"
    read -rp "Create it? [Y/n]: " CREATE_DIR
    if [[ "${CREATE_DIR,,}" != "n" ]]; then
        mkdir -p "$DOCKER_DATA"
        echo -e "${GREEN}Created ${DOCKER_DATA}${NC}"
    fi
fi
echo

# ===========================================
# 2. MEDIA_PATH - NAS media storage
# ===========================================
DEFAULT_MEDIA_PATH="/mnt/unas/media"
echo -e "${BOLD}Media storage path (NAS mount)${NC}"
echo "Where media files live (torrents, movies, TV shows)."
echo "This should be a mounted NAS share (NFS/SMB/etc.)"
echo -e "Default: ${GREEN}${DEFAULT_MEDIA_PATH}${NC}"
read -rp "> Path [${DEFAULT_MEDIA_PATH}]: " INPUT_MEDIA_PATH
MEDIA_PATH="${INPUT_MEDIA_PATH:-$DEFAULT_MEDIA_PATH}"

if [ ! -d "$MEDIA_PATH" ]; then
    echo -e "${YELLOW}Directory does not exist: ${MEDIA_PATH}${NC}"
    echo "Make sure your NAS is mounted before starting media services."
fi
echo

# ===========================================
# 3. DOCKER_SOCK - Docker socket path
# ===========================================
echo -e "${BOLD}Docker socket${NC}"
DETECTED_SOCK="/run/user/$(id -u)/docker.sock"

if [ -S "$DETECTED_SOCK" ]; then
    DOCKER_SOCK="$DETECTED_SOCK"
    echo -e "Detected rootless Docker socket: ${GREEN}${DOCKER_SOCK}${NC}"
elif [ -S "/var/run/docker.sock" ]; then
    DOCKER_SOCK="/var/run/docker.sock"
    echo -e "Detected standard Docker socket: ${GREEN}${DOCKER_SOCK}${NC}"
else
    DOCKER_SOCK="$DETECTED_SOCK"
    echo -e "${YELLOW}No Docker socket found. Using default: ${DOCKER_SOCK}${NC}"
    echo "Is Docker installed and running?"
fi
echo

# ===========================================
# Summary & confirmation
# ===========================================
echo -e "${BOLD}Summary:${NC}"
echo -e "  DOCKER_DATA = ${GREEN}${DOCKER_DATA}${NC}"
echo -e "  MEDIA_PATH  = ${GREEN}${MEDIA_PATH}${NC}"
echo -e "  DOCKER_SOCK = ${GREEN}${DOCKER_SOCK}${NC}"
echo
read -rp "Write these to ${ZSHENV}? [Y/n]: " CONFIRM
if [[ "${CONFIRM,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
fi

# ===========================================
# Write to ~/.zshenv
# ===========================================
# Remove any existing homelab block first
if [ -f "$ZSHENV" ]; then
    # Use temp file to avoid sed -i portability issues
    grep -v "$MARKER_START" "$ZSHENV" | \
    grep -v "$MARKER_END" | \
    grep -v "^export DOCKER_DATA=" | \
    grep -v "^export MEDIA_PATH=" | \
    grep -v "^export DOCKER_SOCK=" > "${ZSHENV}.tmp" || true
    mv "${ZSHENV}.tmp" "$ZSHENV"
fi

cat >> "$ZSHENV" << EOF
${MARKER_START}
export DOCKER_DATA="${DOCKER_DATA}"
export MEDIA_PATH="${MEDIA_PATH}"
export DOCKER_SOCK="${DOCKER_SOCK}"
${MARKER_END}
EOF

echo -e "${GREEN}Wrote to ${ZSHENV}${NC}"

# ===========================================
# Decrypt secrets (if encrypted files exist)
# ===========================================
echo
SECRETS_SCRIPT="${SCRIPT_DIR}/secrets.sh"

if [ -x "$SECRETS_SCRIPT" ]; then
    # Check if any .enc files exist
    ENC_COUNT=$(find "$REPO_DIR" -name '*.enc' -not -path '*/.terraform/*' | wc -l)
    if [ "$ENC_COUNT" -gt 0 ]; then
        if command -v sops >/dev/null 2>&1 && command -v age >/dev/null 2>&1; then
            AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
            if [ -f "$AGE_KEY" ]; then
                echo -e "${BOLD}Found ${ENC_COUNT} encrypted secret files. Decrypting...${NC}"
                "$SECRETS_SCRIPT" decrypt
            else
                echo -e "${YELLOW}Encrypted secrets found but no age key at ${AGE_KEY}${NC}"
                echo -e "Copy your age key from the old machine, then run:"
                echo -e "  ${YELLOW}./scripts/secrets.sh decrypt${NC}"
            fi
        else
            echo -e "${YELLOW}Encrypted secrets found but sops/age not installed${NC}"
            echo -e "Install them, then run: ${YELLOW}./scripts/secrets.sh decrypt${NC}"
        fi
    else
        echo -e "${YELLOW}No encrypted secret files found${NC}"
        echo -e "If this is a fresh setup, create secrets from examples or copy them manually."
    fi
else
    echo -e "${YELLOW}secrets.sh not found — skipping decryption${NC}"
fi

# ===========================================
# Create .env from .env.example if still missing
# ===========================================
echo
ENV_FILE="${REPO_DIR}/.env"
ENV_EXAMPLE="${REPO_DIR}/.env.example"

if [ ! -f "$ENV_FILE" ] && [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo -e "${GREEN}Created .env from .env.example${NC}"
    echo -e "${YELLOW}Fill in your API keys and secrets in .env${NC}"
elif [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}No .env or .env.example found${NC}"
else
    echo -e "${GREEN}.env already exists${NC}"
fi

# ===========================================
# Done
# ===========================================
echo
echo -e "${GREEN}${BOLD}Setup complete!${NC}"
echo
echo -e "Next steps:"
echo -e "  1. Run ${YELLOW}source ~/.zshenv${NC} or open a new terminal"
echo -e "  2. If secrets were not decrypted above:"
echo -e "     a. Copy your age key to ${YELLOW}~/.config/sops/age/keys.txt${NC}"
echo -e "     b. Run ${YELLOW}./scripts/secrets.sh decrypt${NC}"
echo -e "     Or manually create secrets from examples:"
echo -e "       ${YELLOW}cp media-server/buildarr/buildarr-secrets.yml.example media-server/buildarr/buildarr-secrets.yml${NC}"
echo -e "       ${YELLOW}cp media-server/configarr/secrets.yml.example media-server/configarr/secrets.yml${NC}"
echo -e "       ${YELLOW}cp home-assistant/secrets.yaml.example home-assistant/secrets.yaml${NC}"
echo -e "  3. Start all services:"
echo -e "     ${YELLOW}./scripts/start.sh${NC}        # Core stacks (media, monitoring, homepage, HA, tunnel)"
echo -e "     ${YELLOW}./scripts/start.sh --all${NC}  # Also includes Minecraft servers"
