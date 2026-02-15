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
TF_MARKER_START="# --- Homelab Cloudflare/Terraform env (managed by init.sh) ---"
TF_MARKER_END="# --- End Homelab Cloudflare/Terraform env ---"

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
if [ -n "${DOCKER_DATA:-}" ]; then
    echo -e "Using existing DOCKER_DATA from environment: ${GREEN}${DOCKER_DATA}${NC}"
else
    echo -e "Default: ${GREEN}${DEFAULT_DOCKER_DATA}${NC}"
    read -rp "> Path [${DEFAULT_DOCKER_DATA}]: " INPUT_DOCKER_DATA
    DOCKER_DATA="${INPUT_DOCKER_DATA:-$DEFAULT_DOCKER_DATA}"
fi

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
if [ -n "${MEDIA_PATH:-}" ]; then
    echo -e "Using existing MEDIA_PATH from environment: ${GREEN}${MEDIA_PATH}${NC}"
else
    echo -e "Default: ${GREEN}${DEFAULT_MEDIA_PATH}${NC}"
    read -rp "> Path [${DEFAULT_MEDIA_PATH}]: " INPUT_MEDIA_PATH
    MEDIA_PATH="${INPUT_MEDIA_PATH:-$DEFAULT_MEDIA_PATH}"
fi

if [ ! -d "$MEDIA_PATH" ]; then
    echo -e "${YELLOW}Directory does not exist: ${MEDIA_PATH}${NC}"
    echo "Make sure your NAS is mounted before starting media services."
fi

# Offer to configure NAS mount if not already mounted
NAS_MOUNT_SCRIPT="${SCRIPT_DIR}/setup-nas-mount.sh"
if [ -x "$NAS_MOUNT_SCRIPT" ]; then
    if ! mountpoint -q "$MEDIA_PATH" 2>/dev/null; then
        echo
        echo -e "${BOLD}NAS mount setup${NC}"
        echo "The media path is not currently mounted."
        read -rp "Configure NAS mount for ${MEDIA_PATH}? [Y/n]: " SETUP_NAS
        if [[ "${SETUP_NAS,,}" != "n" ]]; then
            "$NAS_MOUNT_SCRIPT" "$MEDIA_PATH"
        fi
    else
        echo -e "${GREEN}NAS already mounted at ${MEDIA_PATH}${NC}"
    fi
fi
echo

# ===========================================
# 3. DOCKER_SOCK - Docker socket path
# ===========================================
echo -e "${BOLD}Docker socket${NC}"
DETECTED_SOCK="/run/user/$(id -u)/docker.sock"

if [ -n "${DOCKER_SOCK:-}" ]; then
    if [ -S "$DOCKER_SOCK" ]; then
        echo -e "Using existing DOCKER_SOCK from environment: ${GREEN}${DOCKER_SOCK}${NC}"
    else
        echo -e "${YELLOW}Existing DOCKER_SOCK does not exist: ${DOCKER_SOCK}${NC}"
        if [ -S "$DETECTED_SOCK" ]; then
            DOCKER_SOCK="$DETECTED_SOCK"
            echo -e "Falling back to detected rootless Docker socket: ${GREEN}${DOCKER_SOCK}${NC}"
        elif [ -S "/var/run/docker.sock" ]; then
            DOCKER_SOCK="/var/run/docker.sock"
            echo -e "Falling back to detected standard Docker socket: ${GREEN}${DOCKER_SOCK}${NC}"
        else
            echo "Is Docker installed and running?"
        fi
    fi
elif [ -S "$DETECTED_SOCK" ]; then
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
# 4. DOCKER_GID - Docker socket group
# ===========================================
echo -e "${BOLD}Docker socket group${NC}"
echo "GID of the Docker socket — used by Homepage to access Docker as non-root."

if [ -n "${DOCKER_GID:-}" ]; then
    echo -e "Using existing DOCKER_GID from environment: ${GREEN}${DOCKER_GID}${NC}"
else
    if [ -S "$DOCKER_SOCK" ]; then
        DETECTED_DOCKER_GID=$(stat -c '%g' "$DOCKER_SOCK")
        echo -e "Detected Docker socket GID: ${GREEN}${DETECTED_DOCKER_GID}${NC}"
    elif getent group docker > /dev/null 2>&1; then
        DETECTED_DOCKER_GID=$(getent group docker | cut -d: -f3)
        echo -e "Detected docker group GID: ${GREEN}${DETECTED_DOCKER_GID}${NC}"
    else
        DETECTED_DOCKER_GID=""
        echo -e "${YELLOW}Could not detect Docker GID — Homepage may not be able to access Docker socket${NC}"
    fi

    if [ -n "$DETECTED_DOCKER_GID" ]; then
        DOCKER_GID="$DETECTED_DOCKER_GID"
    else
        read -rp "> GID (leave empty to skip): " DOCKER_GID
    fi
fi
echo

# ===========================================
# 5. RENDER_GID - GPU render group for HW transcoding
# ===========================================
echo -e "${BOLD}GPU render group${NC}"
echo "Used by Plex for hardware-accelerated transcoding."

if [ -n "${RENDER_GID:-}" ]; then
    echo -e "Using existing RENDER_GID from environment: ${GREEN}${RENDER_GID}${NC}"
else
    if getent group render > /dev/null 2>&1; then
        DETECTED_GID=$(getent group render | cut -d: -f3)
        echo -e "Detected render group GID: ${GREEN}${DETECTED_GID}${NC}"
    elif getent group video > /dev/null 2>&1; then
        DETECTED_GID=$(getent group video | cut -d: -f3)
        echo -e "No render group found. Detected video group GID: ${GREEN}${DETECTED_GID}${NC}"
    else
        DETECTED_GID=""
        echo -e "${YELLOW}No render or video group found — GPU transcoding may not be available${NC}"
    fi

    if [ -n "$DETECTED_GID" ]; then
        read -rp "> GID [${DETECTED_GID}]: " INPUT_RENDER_GID
        RENDER_GID="${INPUT_RENDER_GID:-$DETECTED_GID}"
    else
        read -rp "> GID (leave empty to skip): " RENDER_GID
    fi
fi
echo

# ===========================================
# 6. Home Assistant trusted proxies
# ===========================================
echo -e "${BOLD}Home Assistant trusted proxies${NC}"
echo "IPs/CIDRs that Home Assistant should trust for X-Forwarded-For."
echo "Comma-separated list."
DEFAULT_TRUSTED_PROXIES="127.0.0.1,::1"
MEDIA_NET_SUBNETS=""
if command -v docker >/dev/null 2>&1; then
    MEDIA_NET_SUBNETS=$(docker network inspect media-net \
        --format '{{range .IPAM.Config}}{{.Subnet}},{{end}}' 2>/dev/null | \
        sed 's/,$//')
fi
if [ -n "$MEDIA_NET_SUBNETS" ]; then
    echo -e "Detected media-net subnet(s): ${GREEN}${MEDIA_NET_SUBNETS}${NC}"
    DEFAULT_TRUSTED_PROXIES="${DEFAULT_TRUSTED_PROXIES},${MEDIA_NET_SUBNETS}"
else
    echo -e "${YELLOW}Could not detect media-net subnet(s).${NC}"
fi
read -rp "> Proxies [${DEFAULT_TRUSTED_PROXIES}]: " INPUT_TRUSTED_PROXIES
TRUSTED_PROXIES="${INPUT_TRUSTED_PROXIES:-$DEFAULT_TRUSTED_PROXIES}"
TRUSTED_PROXIES_FILE="${REPO_DIR}/home-assistant/trusted_proxies.yaml"
> "$TRUSTED_PROXIES_FILE"
IFS=',' read -ra PROXY_LIST <<< "$TRUSTED_PROXIES"
for proxy in "${PROXY_LIST[@]}"; do
    proxy="${proxy// /}"
    if [ -n "$proxy" ]; then
        echo "- $proxy" >> "$TRUSTED_PROXIES_FILE"
    fi
done
echo -e "${GREEN}Wrote ${TRUSTED_PROXIES_FILE}${NC}"
echo

# ===========================================
# 7. Optional: Cloudflare/Terraform credentials
# ===========================================
CONFIGURE_TF_ENV=false
TF_CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
TF_AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}"
TF_AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}"

echo -e "${BOLD}Cloudflare/Terraform local credentials (optional)${NC}"
echo "Needed only if you run terraform locally in cloudflare-tunnel/."
echo "Google OAuth values are read from cloudflare-tunnel/terraform.tfvars."
echo "These values are written to ~/.zshenv and loaded in new shells."
read -rp "Configure these now? [y/N]: " SETUP_TF_ENV
if [[ "${SETUP_TF_ENV,,}" == "y" ]]; then
    CONFIGURE_TF_ENV=true

    if [ -n "$TF_CLOUDFLARE_API_TOKEN" ]; then
        read -rp "> CLOUDFLARE_API_TOKEN [keep existing]: " INPUT
        TF_CLOUDFLARE_API_TOKEN="${INPUT:-$TF_CLOUDFLARE_API_TOKEN}"
    else
        read -rp "> CLOUDFLARE_API_TOKEN [leave empty to skip]: " TF_CLOUDFLARE_API_TOKEN
    fi

    if [ -n "$TF_AWS_ACCESS_KEY_ID" ]; then
        read -rp "> CLOUDFLARE_R2_ACCESS_KEY_ID -> AWS_ACCESS_KEY_ID [keep existing]: " INPUT
        TF_AWS_ACCESS_KEY_ID="${INPUT:-$TF_AWS_ACCESS_KEY_ID}"
    else
        read -rp "> CLOUDFLARE_R2_ACCESS_KEY_ID -> AWS_ACCESS_KEY_ID [leave empty to skip]: " TF_AWS_ACCESS_KEY_ID
    fi

    if [ -n "$TF_AWS_SECRET_ACCESS_KEY" ]; then
        read -rsp "> CLOUDFLARE_R2_SECRET_ACCESS_KEY -> AWS_SECRET_ACCESS_KEY [keep existing]: " INPUT
        echo
        TF_AWS_SECRET_ACCESS_KEY="${INPUT:-$TF_AWS_SECRET_ACCESS_KEY}"
    else
        read -rsp "> CLOUDFLARE_R2_SECRET_ACCESS_KEY -> AWS_SECRET_ACCESS_KEY [leave empty to skip]: " TF_AWS_SECRET_ACCESS_KEY
        echo
    fi

    echo -e "${GREEN}Cloudflare/Terraform credentials captured.${NC}"
fi
echo

# ===========================================
# Summary & confirmation
# ===========================================
echo -e "${BOLD}Summary:${NC}"
echo -e "  DOCKER_DATA = ${GREEN}${DOCKER_DATA}${NC}"
echo -e "  MEDIA_PATH  = ${GREEN}${MEDIA_PATH}${NC}"
echo -e "  DOCKER_SOCK = ${GREEN}${DOCKER_SOCK}${NC}"
if [ -n "$DOCKER_GID" ]; then
    echo -e "  DOCKER_GID  = ${GREEN}${DOCKER_GID}${NC}"
else
    echo -e "  DOCKER_GID  = ${YELLOW}(not set)${NC}"
fi
if [ -n "$RENDER_GID" ]; then
    echo -e "  RENDER_GID  = ${GREEN}${RENDER_GID}${NC}"
else
    echo -e "  RENDER_GID  = ${YELLOW}(not set — no GPU transcoding)${NC}"
fi
if $CONFIGURE_TF_ENV; then
    [ -n "$TF_CLOUDFLARE_API_TOKEN" ] && TF_TOKEN_STATUS="set" || TF_TOKEN_STATUS="not set"
    [ -n "$TF_AWS_ACCESS_KEY_ID" ] && TF_R2_ID_STATUS="set" || TF_R2_ID_STATUS="not set"
    [ -n "$TF_AWS_SECRET_ACCESS_KEY" ] && TF_R2_SECRET_STATUS="set" || TF_R2_SECRET_STATUS="not set"
    echo -e "  Terraform local env: ${GREEN}update requested${NC}"
    echo -e "    CLOUDFLARE_API_TOKEN          = ${GREEN}${TF_TOKEN_STATUS}${NC}"
    echo -e "    AWS_ACCESS_KEY_ID             = ${GREEN}${TF_R2_ID_STATUS}${NC}"
    echo -e "    AWS_SECRET_ACCESS_KEY         = ${GREEN}${TF_R2_SECRET_STATUS}${NC}"
    echo -e "    TF_VAR_google_oauth_*         = ${YELLOW}from terraform.tfvars${NC}"
fi
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
    grep -v "^export DOCKER_SOCK=" | \
    grep -v "^export DOCKER_GID=" | \
    grep -v "^export RENDER_GID=" > "${ZSHENV}.tmp" || true
    mv "${ZSHENV}.tmp" "$ZSHENV"
fi

if $CONFIGURE_TF_ENV && [ -f "$ZSHENV" ]; then
    grep -v "$TF_MARKER_START" "$ZSHENV" | \
    grep -v "$TF_MARKER_END" | \
    grep -v "^export CLOUDFLARE_API_TOKEN=" | \
    grep -v "^export AWS_ACCESS_KEY_ID=" | \
    grep -v "^export AWS_SECRET_ACCESS_KEY=" > "${ZSHENV}.tmp" || true
    mv "${ZSHENV}.tmp" "$ZSHENV"
fi

cat >> "$ZSHENV" << EOF
${MARKER_START}
export DOCKER_DATA="${DOCKER_DATA}"
export MEDIA_PATH="${MEDIA_PATH}"
export DOCKER_SOCK="${DOCKER_SOCK}"
export DOCKER_GID="${DOCKER_GID}"
export RENDER_GID="${RENDER_GID}"
${MARKER_END}
EOF

echo -e "${GREEN}Wrote to ${ZSHENV}${NC}"

if $CONFIGURE_TF_ENV; then
cat >> "$ZSHENV" << EOF
${TF_MARKER_START}
export CLOUDFLARE_API_TOKEN="${TF_CLOUDFLARE_API_TOKEN}"
export AWS_ACCESS_KEY_ID="${TF_AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${TF_AWS_SECRET_ACCESS_KEY}"
${TF_MARKER_END}
EOF
echo -e "${GREEN}Wrote Cloudflare/Terraform env block to ${ZSHENV}${NC}"
fi

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
if $CONFIGURE_TF_ENV; then
    echo -e "  1b. Local Terraform is ready to use in ${YELLOW}cloudflare-tunnel/${NC}"
fi
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
