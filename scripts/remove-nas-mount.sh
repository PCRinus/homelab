#!/bin/bash
# ===========================================
# Remove NAS Mount
# ===========================================
# Unmounts and removes the NAS mount configuration.
# Cleans up fstab entry, systemd units, and optionally
# SMB credential files.
#
# Usage:
#   ./scripts/remove-nas-mount.sh                    # Uses default /mnt/unas/media
#   ./scripts/remove-nas-mount.sh /mnt/unas/media    # Specify mount point
# ===========================================

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

DEFAULT_MOUNT="/mnt/unas/media"
MOUNT_POINT="${1:-}"
FSTAB="/etc/fstab"
MARKER="# NAS mount managed by homelab setup"

echo -e "${BOLD}Remove NAS Mount${NC}"
echo

# --- Determine mount point ---
if [ -z "$MOUNT_POINT" ]; then
    read -rp "> Mount point to remove [${DEFAULT_MOUNT}]: " MOUNT_POINT
    MOUNT_POINT="${MOUNT_POINT:-$DEFAULT_MOUNT}"
fi

# --- Show current state ---
echo
echo -e "${BOLD}Current state:${NC}"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo -e "  Mount:  ${GREEN}active${NC}"
    df -h "$MOUNT_POINT" | tail -1 | sed 's/^/    /'
else
    echo -e "  Mount:  ${YELLOW}not mounted${NC}"
fi

FSTAB_ENTRY=$(grep "[[:space:]]${MOUNT_POINT}[[:space:]]" "$FSTAB" 2>/dev/null || true)
if [ -n "$FSTAB_ENTRY" ]; then
    echo -e "  fstab:  ${GREEN}entry found${NC}"
    echo "    ${FSTAB_ENTRY}"
else
    echo -e "  fstab:  ${YELLOW}no entry${NC}"
fi

# Convert mount path to systemd unit name: /mnt/unas/media -> mnt-unas-media
SYSTEMD_UNIT=$(echo "$MOUNT_POINT" | sed 's|^/||;s|/$||;s|/|-|g')
AUTOMOUNT_ACTIVE=false
MOUNT_ACTIVE=false

if systemctl is-active "${SYSTEMD_UNIT}.automount" >/dev/null 2>&1; then
    AUTOMOUNT_ACTIVE=true
    echo -e "  Automount unit: ${GREEN}active${NC} (${SYSTEMD_UNIT}.automount)"
fi
if systemctl is-active "${SYSTEMD_UNIT}.mount" >/dev/null 2>&1; then
    MOUNT_ACTIVE=true
    echo -e "  Mount unit: ${GREEN}active${NC} (${SYSTEMD_UNIT}.mount)"
fi

# Check for SMB credentials file
CREDS_FILE=""
if [ -n "$FSTAB_ENTRY" ]; then
    CREDS_FILE=$(echo "$FSTAB_ENTRY" | grep -oP 'credentials=\K[^,\s]+' || true)
fi

if [ -z "$FSTAB_ENTRY" ] && ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo
    echo -e "${YELLOW}Nothing to remove — no fstab entry and not mounted.${NC}"
    exit 0
fi

# --- Confirm ---
echo
read -rp "Remove this NAS mount? (requires sudo) [Y/n]: " CONFIRM
if [[ "${CONFIRM,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
fi
echo

# --- 1. Stop systemd automount/mount units ---
if $AUTOMOUNT_ACTIVE; then
    echo "Stopping automount unit..."
    sudo systemctl stop "${SYSTEMD_UNIT}.automount" 2>/dev/null || true
    echo -e "${GREEN}Stopped ${SYSTEMD_UNIT}.automount${NC}"
fi

# --- 2. Unmount ---
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "Unmounting ${MOUNT_POINT}..."
    if sudo umount "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${GREEN}Unmounted${NC}"
    elif sudo umount -l "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${YELLOW}Lazy-unmounted (some processes may still reference it)${NC}"
    else
        echo -e "${RED}Failed to unmount — check for processes using the mount: ${YELLOW}lsof +f -- ${MOUNT_POINT}${NC}"
    fi
fi

if $MOUNT_ACTIVE; then
    sudo systemctl stop "${SYSTEMD_UNIT}.mount" 2>/dev/null || true
fi

# --- 3. Remove fstab entry ---
if [ -n "$FSTAB_ENTRY" ]; then
    echo "Removing fstab entry..."
    sudo cp "$FSTAB" "${FSTAB}.bak"
    # Remove the marker comment line and the mount entry
    sudo grep -v -F "$MARKER" "$FSTAB" | sudo grep -v "[[:space:]]${MOUNT_POINT}[[:space:]]" | sudo tee "${FSTAB}.tmp" > /dev/null
    sudo mv "${FSTAB}.tmp" "$FSTAB"
    echo -e "${GREEN}Removed from /etc/fstab${NC} (backup at ${FSTAB}.bak)"
fi

# --- 4. Reload systemd ---
echo "Reloading systemd daemon..."
sudo systemctl daemon-reload
echo -e "${GREEN}Systemd reloaded${NC}"

# --- 5. Clean up SMB credentials (if any) ---
if [ -n "$CREDS_FILE" ] && [ -f "$CREDS_FILE" ]; then
    read -rp "Remove SMB credentials file ${CREDS_FILE}? [Y/n]: " DEL_CREDS
    if [[ "${DEL_CREDS,,}" != "n" ]]; then
        sudo rm -f "$CREDS_FILE"
        echo -e "${GREEN}Removed ${CREDS_FILE}${NC}"
    fi
fi

# --- 6. Optionally remove mount point directory ---
if [ -d "$MOUNT_POINT" ]; then
    # Only offer to remove if it's empty
    if [ -z "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; then
        read -rp "Remove empty mount point directory ${MOUNT_POINT}? [Y/n]: " DEL_DIR
        if [[ "${DEL_DIR,,}" != "n" ]]; then
            sudo rmdir "$MOUNT_POINT" 2>/dev/null || true
            echo -e "${GREEN}Removed ${MOUNT_POINT}${NC}"
        fi
    fi
fi

echo
echo -e "${GREEN}${BOLD}NAS mount removed!${NC}"
echo
echo -e "To reconfigure, run: ${YELLOW}./scripts/setup-nas-mount.sh${NC}"
