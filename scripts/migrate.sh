#!/bin/bash
# ===========================================
# Migrate homelab data from old machine
# ===========================================
# Rsyncs persistent container data ($DOCKER_DATA) from the old server
# to this machine, one stack at a time.
#
# For each stack it will:
#   1. SSH to the old machine and stop the stack
#   2. Rsync the data directories for that stack
#   3. Start the stack locally
#   4. Verify containers are running
#   5. Ask to proceed to the next stack
#
# Usage:
#   ./scripts/migrate.sh                    # Migrate core stacks
#   ./scripts/migrate.sh --all              # Include Minecraft servers
#   ./scripts/migrate.sh --dry-run          # Preview rsync without changes
#   ./scripts/migrate.sh --skip-stop        # Don't stop services on old machine
#   ./scripts/migrate.sh --stack media-server  # Migrate a single stack
#   ./scripts/migrate.sh --ssh-keys         # Migrate GitHub Actions SSH keys only
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Configuration ---
OLD_HOST="homelab"
OLD_DOCKER_DATA="/home/mircea/docker"
OLD_COMPOSE_DIR="/home/mircea/compose-files"

# --- Parse arguments ---
INCLUDE_MINECRAFT=false
DRY_RUN=false
SKIP_STOP=false
SINGLE_STACK=""
MIGRATE_SSH_KEYS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all) INCLUDE_MINECRAFT=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --skip-stop) SKIP_STOP=true; shift ;;
        --stack) SINGLE_STACK="$2"; shift 2 ;;
        --ssh-keys) MIGRATE_SSH_KEYS=true; shift ;;
        --host) OLD_HOST="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo
            echo "Options:"
            echo "  --all           Include Minecraft servers"
            echo "  --dry-run       Preview rsync without making changes"
            echo "  --skip-stop     Don't stop services on old machine"
            echo "  --stack NAME    Migrate a single stack"
            echo "  --ssh-keys      Migrate GitHub Actions SSH keys only"
            echo "  --host HOST     Override old machine hostname (default: homelab)"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *) echo -e "${RED}Unknown option: $1${NC}"; exit 1 ;;
    esac
done

# --- Map stacks to their $DOCKER_DATA subdirectories ---
# Order: low-risk first, cloudflare-tunnel last (DNS cutover)
declare -A STACK_DATA
STACK_DATA[monitoring]="gatus"
STACK_DATA[homepage]="homepage"
STACK_DATA[home-assistant]="home-assistant"
STACK_DATA[media-server]="qbittorrent sonarr radarr prowlarr overseerr plex bazarr tautulli configarr"
STACK_DATA[minecraft-servers]="minecraft-server-survival-island minecraft-server-world-generation"
# cloudflare-tunnel has no persistent data in DOCKER_DATA

MIGRATION_ORDER=(
    "monitoring"
    "homepage"
    "media-server"
    "home-assistant"
    "cloudflare-tunnel"
)

# --- Preflight checks ---
if [ -z "$DOCKER_DATA" ]; then
    echo -e "${RED}DOCKER_DATA not set. Run ./scripts/init.sh first, then source ~/.zshenv${NC}"
    exit 1
fi

# If DOCKER_SOCK is set but DOCKER_HOST isn't, export DOCKER_HOST so the
# docker CLI uses the correct socket (important for rootless Docker).
if [ -n "$DOCKER_SOCK" ] && [ -z "$DOCKER_HOST" ]; then
    export DOCKER_HOST="unix://${DOCKER_SOCK}"
fi

echo -e "${BLUE}${BOLD}========================================${NC}"
echo -e "${BLUE}${BOLD}  Homelab Migration${NC}"
echo -e "${BLUE}${BOLD}========================================${NC}"
echo
echo -e "Old machine:    ${BOLD}${OLD_HOST}${NC}"
echo -e "Remote data:    ${BOLD}${OLD_DOCKER_DATA}${NC}"
echo -e "Local data:     ${BOLD}${DOCKER_DATA}${NC}"
echo -e "Dry run:        ${BOLD}${DRY_RUN}${NC}"
echo -e "Skip stop:      ${BOLD}${SKIP_STOP}${NC}"
echo

# --- Test SSH connectivity ---
echo -e "${BOLD}Testing SSH connection to ${OLD_HOST}...${NC}"
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$OLD_HOST" "echo ok" > /dev/null 2>&1; then
    echo -e "${RED}Cannot SSH to ${OLD_HOST}${NC}"
    echo -e "Make sure you can ${YELLOW}ssh ${OLD_HOST}${NC} without a password prompt."
    echo -e "Set up SSH key auth or add a Host entry to ~/.ssh/config"
    exit 1
fi
echo -e "${GREEN}SSH connection OK${NC}"
echo

migrate_ssh_keys() {
    local remote_ssh_dir="~/.ssh"
    local local_ssh_dir="$HOME/.ssh"
    local timestamp
    timestamp=$(date +%Y%m%d%H%M%S)
    local keys=(
        "github_actions_homelab"
        "github_actions_homelab.pub"
    )

    mkdir -p "$local_ssh_dir"

    echo -e "${BOLD}Migrating GitHub Actions SSH keys from ${OLD_HOST}...${NC}"

    for key in "${keys[@]}"; do
        if ! ssh "$OLD_HOST" "test -f ${remote_ssh_dir}/${key}"; then
            echo -e "  ${YELLOW}Missing on remote: ${remote_ssh_dir}/${key}${NC}"
            continue
        fi

        if [ -f "${local_ssh_dir}/${key}" ]; then
            mv "${local_ssh_dir}/${key}" "${local_ssh_dir}/${key}.bak-${timestamp}"
            echo -e "  ${YELLOW}Backed up existing ${key} to .bak-${timestamp}${NC}"
        fi

        rsync -avP "${OLD_HOST}:${remote_ssh_dir}/${key}" "${local_ssh_dir}/${key}"
    done

    if [ -f "${local_ssh_dir}/github_actions_homelab" ]; then
        chmod 600 "${local_ssh_dir}/github_actions_homelab"
    fi
    if [ -f "${local_ssh_dir}/github_actions_homelab.pub" ]; then
        chmod 644 "${local_ssh_dir}/github_actions_homelab.pub"
    fi

    if [ -f "${local_ssh_dir}/github_actions_homelab.pub" ]; then
        local pub_key
        pub_key=$(cat "${local_ssh_dir}/github_actions_homelab.pub")
        touch "${local_ssh_dir}/authorized_keys"
        chmod 600 "${local_ssh_dir}/authorized_keys"
        if ! grep -Fq "$pub_key" "${local_ssh_dir}/authorized_keys"; then
            echo "$pub_key" >> "${local_ssh_dir}/authorized_keys"
            echo -e "  ${GREEN}Added public key to authorized_keys${NC}"
        else
            echo -e "  ${GREEN}Public key already present in authorized_keys${NC}"
        fi
    fi

    echo -e "${GREEN}SSH key migration complete.${NC}"
    echo -e "Update the GitHub Actions secret SSH_PRIVATE_KEY with:${NC}"
    echo -e "  ${YELLOW}cat ~/.ssh/github_actions_homelab${NC}"
}

if $MIGRATE_SSH_KEYS; then
    migrate_ssh_keys
    exit 0
fi

# --- Helper functions ---
rsync_data() {
    local dir_name="$1"
    local extra_args=()

    if $DRY_RUN; then
        extra_args+=(--dry-run)
    fi

    echo -e "  Syncing ${BOLD}${dir_name}${NC}..."

    # Create local directory if it doesn't exist
    if ! $DRY_RUN; then
        mkdir -p "${DOCKER_DATA}/${dir_name}"
    fi

    # Use sudo rsync on the remote side to handle rootless Docker's
    # subordinate UID-owned files that the SSH user can't read directly.
    rsync -avP --delete \
        --rsync-path="sudo rsync" \
        --numeric-ids \
        "${extra_args[@]}" \
        "${OLD_HOST}:${OLD_DOCKER_DATA}/${dir_name}/" \
        "${DOCKER_DATA}/${dir_name}/" 2>&1 | \
        tail -5  # Show just the summary

    local rc=${PIPESTATUS[0]}
    # Code 23 = some file attributes couldn't transfer (common with rootless
    # Docker's user namespace remapping). Data transfers fine — treat as warning.
    if [ "$rc" -eq 23 ]; then
        echo -e "  ${YELLOW}Warning: some file attributes could not be preserved (rsync code 23)${NC}"
        echo -e "  ${YELLOW}This is normal with rootless Docker — data transferred OK${NC}"
        return 0
    fi
    return "$rc"
}

stop_remote_stack() {
    local stack="$1"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}Dry run — skipping remote stop${NC}"
        return 0
    fi

    if $SKIP_STOP; then
        echo -e "  ${YELLOW}Skipping remote stop (--skip-stop)${NC}"
        return 0
    fi

    echo -e "  Stopping ${BOLD}${stack}${NC} on ${OLD_HOST}..."

    if [[ "$stack" == "minecraft-servers" ]]; then
        ssh "$OLD_HOST" "cd ${OLD_COMPOSE_DIR}/${stack} && \
            for f in *.compose.yml; do \
                [ \"\$f\" = 'common.compose.yml' ] && continue; \
                docker compose -f \"\$f\" down 2>/dev/null; \
            done" 2>&1 || true
    elif [[ "$stack" == "cloudflare-tunnel" ]]; then
        # Cloudflare tunnel: just stop, don't remove the network dependencies
        ssh "$OLD_HOST" "cd ${OLD_COMPOSE_DIR}/${stack} && docker compose down" 2>&1 || true
    else
        ssh "$OLD_HOST" "cd ${OLD_COMPOSE_DIR}/${stack} && docker compose down" 2>&1 || true
    fi
}

start_local_stack() {
    local stack="$1"

    if $DRY_RUN; then
        echo -e "  ${YELLOW}Dry run — skipping local start${NC}"
        return 0
    fi

    echo -e "  Starting ${BOLD}${stack}${NC} locally..."

    if [[ "$stack" == "minecraft-servers" ]]; then
        cd "${REPO_DIR}/${stack}"
        for f in *.compose.yml; do
            [[ "$f" == "common.compose.yml" ]] && continue
            docker compose -f "$f" up -d 2>&1
        done
    else
        local script="${REPO_DIR}/${stack}/start.sh"
        if [ -x "$script" ]; then
            "$script" 2>&1
        else
            cd "${REPO_DIR}/${stack}" && docker compose up -d 2>&1
        fi
    fi
}

verify_stack() {
    local stack="$1"

    if $DRY_RUN; then
        return 0
    fi

    echo -e "  Verifying containers..."
    sleep 3  # Give containers a moment to start

    local compose_dir="${REPO_DIR}/${stack}"
    if [[ "$stack" == "minecraft-servers" ]]; then
        cd "$compose_dir"
        local all_ok=true
        for f in *.compose.yml; do
            [[ "$f" == "common.compose.yml" ]] && continue
            if ! docker compose -f "$f" ps --status running --quiet 2>/dev/null | grep -q .; then
                echo -e "  ${RED}Some containers from ${f} are not running${NC}"
                all_ok=false
            fi
        done
        $all_ok
    else
        cd "$compose_dir"
        local running
        running=$(docker compose ps --status running --quiet 2>/dev/null | wc -l)
        local total
        total=$(docker compose ps --quiet 2>/dev/null | wc -l)

        if [ "$running" -eq "$total" ] && [ "$total" -gt 0 ]; then
            echo -e "  ${GREEN}All ${running} container(s) running${NC}"
            return 0
        else
            echo -e "  ${RED}Only ${running}/${total} containers running${NC}"
            docker compose ps 2>/dev/null
            return 1
        fi
    fi
}

calculate_remote_size() {
    local dirs="$1"
    local size_cmd="du -sh"
    for d in $dirs; do
        size_cmd+=" ${OLD_DOCKER_DATA}/${d} 2>/dev/null;"
    done
    ssh "$OLD_HOST" "$size_cmd" 2>/dev/null || echo "  (could not determine size)"
}

# --- Determine which stacks to migrate ---
if [ -n "$SINGLE_STACK" ]; then
    STACKS_TO_MIGRATE=("$SINGLE_STACK")
else
    STACKS_TO_MIGRATE=("${MIGRATION_ORDER[@]}")
    if $INCLUDE_MINECRAFT; then
        STACKS_TO_MIGRATE+=("minecraft-servers")
    fi
fi

# --- Main migration loop ---
MIGRATED=()
FAILED=()
SKIPPED=()

for stack in "${STACKS_TO_MIGRATE[@]}"; do
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Migrating: ${stack}${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo

    data_dirs="${STACK_DATA[$stack]:-}"

    # Show what will be synced
    if [ -n "$data_dirs" ]; then
        echo -e "  Data directories: ${YELLOW}${data_dirs}${NC}"
        echo -e "  Remote sizes:"
        calculate_remote_size "$data_dirs"
    else
        echo -e "  ${YELLOW}No persistent data to sync (config-only stack)${NC}"
    fi
    echo

    # Confirm before proceeding
    if [ -z "$SINGLE_STACK" ]; then
        echo -ne "  ${BOLD}Proceed with ${stack}? [Y/n/s(kip)]: ${NC}"
        read -r confirm
        case "${confirm,,}" in
            n) echo -e "  ${RED}Aborting migration${NC}"; exit 1 ;;
            s) echo -e "  ${YELLOW}Skipping ${stack}${NC}"; SKIPPED+=("$stack"); echo; continue ;;
        esac
    fi
    echo

    # Step 1: Stop remote
    if [ -n "$data_dirs" ]; then
        stop_remote_stack "$stack"
        echo
    fi

    # Step 2: Rsync data
    if [ -n "$data_dirs" ]; then
        SYNC_FAILED=false
        for dir in $data_dirs; do
            if ! rsync_data "$dir"; then
                echo -e "  ${RED}Failed to sync ${dir}${NC}"
                SYNC_FAILED=true
            fi
        done
        echo

        if $SYNC_FAILED; then
            echo -e "  ${RED}Some directories failed to sync${NC}"
            echo -ne "  ${BOLD}Continue anyway? [y/N]: ${NC}"
            read -r cont
            if [[ "${cont,,}" != "y" ]]; then
                FAILED+=("$stack")
                echo
                continue
            fi
        fi
    fi

    # Step 3: Start locally
    if ! start_local_stack "$stack"; then
        echo -e "  ${RED}Failed to start ${stack} locally${NC}"
        FAILED+=("$stack")
        echo
        continue
    fi
    echo

    # Step 4: Verify
    if verify_stack "$stack"; then
        MIGRATED+=("$stack")
        echo -e "  ${GREEN}✅ ${stack} migrated successfully${NC}"
    else
        FAILED+=("$stack")
        echo -e "  ${RED}❌ ${stack} may have issues — check logs${NC}"
        echo -ne "  ${BOLD}Continue to next stack? [Y/n]: ${NC}"
        read -r cont
        if [[ "${cont,,}" == "n" ]]; then
            break
        fi
    fi
    echo
done

# --- Summary ---
echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Migration Summary${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
if [ ${#MIGRATED[@]} -gt 0 ]; then
    echo -e "${GREEN}Migrated:${NC} ${MIGRATED[*]}"
fi
if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped:${NC}  ${SKIPPED[*]}"
fi
if [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}Failed:${NC}   ${FAILED[*]}"
fi
echo
if [ ${#FAILED[@]} -eq 0 ] && [ ${#SKIPPED[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}All stacks migrated successfully!${NC}"
    echo
    echo -e "Next steps:"
    echo -e "  1. Verify services are working at their URLs"
    echo -e "  2. Keep the old machine off (but available) for ~2 weeks"
    echo -e "  3. Once confident, wipe the old machine's Docker data"
elif [ ${#FAILED[@]} -gt 0 ]; then
    echo -e "${RED}${BOLD}Some stacks failed — check the output above${NC}"
    echo -e "Re-run individual stacks with: ${YELLOW}./scripts/migrate.sh --stack <name>${NC}"
    exit 1
fi
