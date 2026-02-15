#!/bin/bash
# ===========================================
# NAS Mount Setup
# ===========================================
# Configures a persistent NAS mount via /etc/fstab.
# Supports NFS and SMB (CIFS) shares.
#
# Can be run standalone or called from init.sh.
#
# Usage:
#   ./scripts/setup-nas-mount.sh                      # Interactive
#   ./scripts/setup-nas-mount.sh /mnt/unas/media      # Pre-set mount point
# ===========================================

set -e

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Accept mount point as argument (from init.sh) or ask
MOUNT_POINT="${1:-}"
DEFAULT_MOUNT_POINT="${NAS_SETUP_DEFAULT_MOUNT_POINT:-/mnt/unas/media}"
DEFAULT_PROTOCOL="${NAS_SETUP_DEFAULT_PROTOCOL:-nfs}"
DEFAULT_SERVER="${NAS_SETUP_DEFAULT_SERVER:-}"
DEFAULT_SHARE="${NAS_SETUP_DEFAULT_SHARE:-}"

echo -e "${BLUE}${BOLD}========================================${NC}"
echo -e "${BLUE}${BOLD}  NAS Mount Setup${NC}"
echo -e "${BLUE}${BOLD}========================================${NC}"
echo

# --- Check for required tools ---
check_deps() {
    local missing=()

    if ! command -v mount >/dev/null 2>&1; then
        missing+=("mount")
    fi

    # We'll check protocol-specific deps after selection
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        exit 1
    fi
}

check_deps

# ===========================================
# 1. Mount point
# ===========================================
if [ -z "$MOUNT_POINT" ]; then
    echo -e "${BOLD}Mount point${NC}"
    echo "Where should the NAS share be mounted on this machine?"
    read -rp "> Path [${DEFAULT_MOUNT_POINT}]: " MOUNT_POINT
    MOUNT_POINT="${MOUNT_POINT:-$DEFAULT_MOUNT_POINT}"
    echo
fi

# Check if already mounted
if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo -e "${GREEN}${MOUNT_POINT} is already mounted.${NC}"
    df -h "$MOUNT_POINT" | tail -1
    echo
    read -rp "Reconfigure anyway? [y/N]: " RECONFIG
    if [[ "${RECONFIG,,}" != "y" ]]; then
        echo -e "${GREEN}Keeping existing mount.${NC}"
        exit 0
    fi
    echo
fi

# ===========================================
# 2. Protocol selection
# ===========================================
echo -e "${BOLD}Share protocol${NC}"
echo "  1) NFS  — Network File System (common on Linux NAS, TrueNAS, Synology)"
echo "  2) SMB  — Windows/Samba share (CIFS)"
if [ "$DEFAULT_PROTOCOL" = "cifs" ]; then
    DEFAULT_PROTO_CHOICE="2"
else
    DEFAULT_PROTO_CHOICE="1"
fi
read -rp "> Protocol [${DEFAULT_PROTO_CHOICE}]: " PROTO_CHOICE
case "${PROTO_CHOICE:-$DEFAULT_PROTO_CHOICE}" in
    2|smb|SMB|cifs|CIFS)
        PROTOCOL="cifs"
        ;;
    *)
        PROTOCOL="nfs"
        ;;
esac
echo -e "Selected: ${GREEN}${PROTOCOL}${NC}"
echo

# ===========================================
# 3. NAS server address
# ===========================================
echo -e "${BOLD}NAS server address${NC}"
echo "IP address or hostname of your NAS."
if [ -n "$DEFAULT_SERVER" ]; then
    read -rp "> Server [${DEFAULT_SERVER}]: " NAS_SERVER
    NAS_SERVER="${NAS_SERVER:-$DEFAULT_SERVER}"
else
    read -rp "> Server: " NAS_SERVER
fi

if [ -z "$NAS_SERVER" ]; then
    echo -e "${RED}Server address is required.${NC}"
    exit 1
fi
echo

# ===========================================
# 4. Share name / export path
# ===========================================
if [ "$PROTOCOL" = "nfs" ]; then
    echo -e "${BOLD}NFS export path${NC}"
    echo "The path of the shared folder on the NAS (e.g., /volume1/media, /mnt/pool/media)"

    # Try to discover NFS exports
    EXPORT_PATHS=()
    if command -v showmount >/dev/null 2>&1; then
        echo -e "${YELLOW}Querying NFS exports from ${NAS_SERVER}...${NC}"
        EXPORTS=$(showmount -e "$NAS_SERVER" 2>/dev/null | tail -n +2 || true)
        if [ -n "$EXPORTS" ]; then
            # Parse export paths into an array
            while IFS= read -r line; do
                path=$(echo "$line" | awk '{print $1}')
                allowed=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
                EXPORT_PATHS+=("$path")
                EXPORT_ALLOWED+=("$allowed")
            done <<< "$EXPORTS"

            echo -e "${GREEN}Available exports:${NC}"
            for i in "${!EXPORT_PATHS[@]}"; do
                echo -e "  ${BOLD}$((i+1)))${NC} ${EXPORT_PATHS[$i]}  ${YELLOW}(${EXPORT_ALLOWED[$i]})${NC}"
            done
            echo
            if [ ${#EXPORT_PATHS[@]} -eq 1 ]; then
                read -rp "> Select export [1] or type a path: " EXPORT_CHOICE
                EXPORT_CHOICE="${EXPORT_CHOICE:-1}"
            else
                read -rp "> Select export (1-${#EXPORT_PATHS[@]}) or type a path: " EXPORT_CHOICE
            fi

            # Check if input is a number (selection) or a path
            if [[ "$EXPORT_CHOICE" =~ ^[0-9]+$ ]] && [ "$EXPORT_CHOICE" -ge 1 ] && [ "$EXPORT_CHOICE" -le ${#EXPORT_PATHS[@]} ]; then
                NAS_SHARE="${EXPORT_PATHS[$((EXPORT_CHOICE-1))]}"
                echo -e "Selected: ${GREEN}${NAS_SHARE}${NC}"
            else
                NAS_SHARE="$EXPORT_CHOICE"
            fi
        else
            echo -e "${YELLOW}Could not list exports (NAS may block showmount).${NC}"
            if [ -n "$DEFAULT_SHARE" ]; then
                read -rp "> Export path [${DEFAULT_SHARE}]: " NAS_SHARE
                NAS_SHARE="${NAS_SHARE:-$DEFAULT_SHARE}"
            else
                read -rp "> Export path: " NAS_SHARE
            fi
        fi
    else
        if [ -n "$DEFAULT_SHARE" ]; then
            read -rp "> Export path [${DEFAULT_SHARE}]: " NAS_SHARE
            NAS_SHARE="${NAS_SHARE:-$DEFAULT_SHARE}"
        else
            read -rp "> Export path: " NAS_SHARE
        fi
    fi

    if [ -z "$NAS_SHARE" ]; then
        echo -e "${RED}Export path is required.${NC}"
        exit 1
    fi
else
    echo -e "${BOLD}SMB share name${NC}"
    echo "The share name on the NAS (e.g., media, Media, shared)"

    # Try to discover SMB shares
    if command -v smbclient >/dev/null 2>&1; then
        echo -e "${YELLOW}Querying SMB shares from ${NAS_SERVER}...${NC}"
        SHARES=$(smbclient -N -L "$NAS_SERVER" 2>/dev/null | grep "Disk" | awk '{print $1}' || true)
        if [ -n "$SHARES" ]; then
            echo -e "${GREEN}Available shares:${NC}"
            echo "$SHARES" | sed 's/^/  /'
        else
            echo -e "${YELLOW}Could not list shares (may need credentials).${NC}"
        fi
    fi

    if [ -n "$DEFAULT_SHARE" ]; then
        read -rp "> Share name [${DEFAULT_SHARE}]: " NAS_SHARE
        NAS_SHARE="${NAS_SHARE:-$DEFAULT_SHARE}"
    else
        read -rp "> Share name: " NAS_SHARE
    fi
    if [ -z "$NAS_SHARE" ]; then
        echo -e "${RED}Share name is required.${NC}"
        exit 1
    fi
fi
echo

# ===========================================
# 5. Protocol-specific options
# ===========================================
if [ "$PROTOCOL" = "nfs" ]; then
    # Check NFS client tools
    if ! command -v mount.nfs >/dev/null 2>&1 && [ ! -f /sbin/mount.nfs ]; then
        echo -e "${YELLOW}NFS client utilities not found.${NC}"
        echo -e "Install with: ${YELLOW}sudo apt install nfs-common${NC} (Debian/Ubuntu)"
        echo -e "          or: ${YELLOW}sudo dnf install nfs-utils${NC}  (Fedora/RHEL)"
        read -rp "Continue anyway? [y/N]: " CONTINUE
        if [[ "${CONTINUE,,}" != "y" ]]; then
            exit 1
        fi
    fi

    # NFS source format: server:/export
    FSTAB_SOURCE="${NAS_SERVER}:${NAS_SHARE}"
    FSTAB_TYPE="nfs"

    echo -e "${BOLD}NFS mount options${NC}"
    DEFAULT_NFS_OPTS="rw,soft,intr,timeo=150,retrans=3,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30"
    echo -e "Default: ${GREEN}${DEFAULT_NFS_OPTS}${NC}"
    echo "  rw             — Read/write access"
    echo "  soft,intr      — Don't hang if NAS is unreachable"
    echo "  _netdev,nofail — Wait for network, don't block boot if unavailable"
    echo "  x-systemd.*    — Systemd automount (mount on first access)"
    read -rp "> Options [accept defaults]: " CUSTOM_OPTS
    MOUNT_OPTS="${CUSTOM_OPTS:-$DEFAULT_NFS_OPTS}"

else
    # Check CIFS client tools
    if ! command -v mount.cifs >/dev/null 2>&1 && [ ! -f /sbin/mount.cifs ]; then
        echo -e "${YELLOW}CIFS/SMB client utilities not found.${NC}"
        echo -e "Install with: ${YELLOW}sudo apt install cifs-utils${NC} (Debian/Ubuntu)"
        echo -e "          or: ${YELLOW}sudo dnf install cifs-utils${NC}  (Fedora/RHEL)"
        read -rp "Continue anyway? [y/N]: " CONTINUE
        if [[ "${CONTINUE,,}" != "y" ]]; then
            exit 1
        fi
    fi

    # SMB source format: //server/share
    FSTAB_SOURCE="//${NAS_SERVER}/${NAS_SHARE}"
    FSTAB_TYPE="cifs"

    # SMB credentials
    echo -e "${BOLD}SMB credentials${NC}"
    echo "If your share requires authentication, enter username/password."
    echo "Leave blank for guest/anonymous access."
    read -rp "> Username (blank for guest): " SMB_USER
    echo

    if [ -n "$SMB_USER" ]; then
        read -rsp "> Password: " SMB_PASS
        echo
        echo

        # Store credentials securely
        CREDS_FILE="/etc/nas-credentials-$(echo "$NAS_SERVER" | tr '.' '-')"
        echo -e "${BOLD}Credentials will be stored in: ${GREEN}${CREDS_FILE}${NC}"
        echo "  (root-only readable, permissions 600)"

        CREDS_CONTENT="username=${SMB_USER}\npassword=${SMB_PASS}"
        CRED_OPTS="credentials=${CREDS_FILE}"
    else
        CREDS_FILE=""
        CRED_OPTS="guest"
    fi

    CURRENT_UID=$(id -u)
    CURRENT_GID=$(id -g)

    DEFAULT_SMB_OPTS="${CRED_OPTS},uid=${CURRENT_UID},gid=${CURRENT_GID},iocharset=utf8,file_mode=0775,dir_mode=0775,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30"
    echo -e "${BOLD}SMB mount options${NC}"
    echo -e "Default: ${GREEN}${DEFAULT_SMB_OPTS}${NC}"
    echo "  uid/gid        — Map files to your user (rootless Docker needs this)"
    echo "  _netdev,nofail — Wait for network, don't block boot if unavailable"
    echo "  x-systemd.*    — Systemd automount (mount on first access)"
    read -rp "> Options [accept defaults]: " CUSTOM_OPTS
    MOUNT_OPTS="${CUSTOM_OPTS:-$DEFAULT_SMB_OPTS}"
fi
echo

# ===========================================
# Summary & confirmation
# ===========================================
FSTAB_LINE="${FSTAB_SOURCE}  ${MOUNT_POINT}  ${FSTAB_TYPE}  ${MOUNT_OPTS}  0  0"

echo -e "${BOLD}Summary:${NC}"
echo -e "  Protocol    : ${GREEN}${PROTOCOL}${NC}"
echo -e "  Source      : ${GREEN}${FSTAB_SOURCE}${NC}"
echo -e "  Mount point : ${GREEN}${MOUNT_POINT}${NC}"
echo -e "  Options     : ${GREEN}${MOUNT_OPTS}${NC}"
if [ "$PROTOCOL" = "cifs" ] && [ -n "$CREDS_FILE" ]; then
    echo -e "  Credentials : ${GREEN}${CREDS_FILE}${NC}"
fi
echo
echo -e "${BOLD}fstab entry:${NC}"
echo -e "  ${YELLOW}${FSTAB_LINE}${NC}"
echo
read -rp "Apply this configuration? (requires sudo) [Y/n]: " CONFIRM
if [[ "${CONFIRM,,}" == "n" ]]; then
    echo "Aborted."
    exit 0
fi

# ===========================================
# Apply configuration
# ===========================================

# 1. Create mount point
if [ ! -d "$MOUNT_POINT" ]; then
    echo -e "Creating mount point ${MOUNT_POINT}..."
    sudo mkdir -p "$MOUNT_POINT"
    echo -e "${GREEN}Created ${MOUNT_POINT}${NC}"
fi

# 2. Write SMB credentials file (if applicable)
if [ "$PROTOCOL" = "cifs" ] && [ -n "$CREDS_FILE" ]; then
    echo -e "Writing credentials to ${CREDS_FILE}..."
    echo -e "$CREDS_CONTENT" | sudo tee "$CREDS_FILE" > /dev/null
    sudo chmod 600 "$CREDS_FILE"
    echo -e "${GREEN}Credentials saved (mode 600)${NC}"
fi

# 3. Update /etc/fstab
# Remove any existing entry for this mount point
FSTAB="/etc/fstab"
MARKER="# NAS mount managed by homelab setup"

if sudo grep -q "${MOUNT_POINT}" "$FSTAB" 2>/dev/null; then
    echo -e "${YELLOW}Removing existing fstab entry for ${MOUNT_POINT}...${NC}"
    sudo cp "$FSTAB" "${FSTAB}.bak"
    # Filter out the marker comment and any line containing this mount point
    sudo grep -v -F "$MARKER" "$FSTAB" | sudo grep -v "[[:space:]]${MOUNT_POINT}[[:space:]]" | sudo tee "${FSTAB}.tmp" > /dev/null
    sudo mv "${FSTAB}.tmp" "$FSTAB"
fi

echo -e "Adding fstab entry..."
echo -e "\n${MARKER}\n${FSTAB_LINE}" | sudo tee -a "$FSTAB" > /dev/null
echo -e "${GREEN}Updated /etc/fstab${NC}"

# 4. Reload systemd (for x-systemd.automount entries)
if command -v systemctl >/dev/null 2>&1; then
    echo "Reloading systemd daemon..."
    sudo systemctl daemon-reload
fi

# 5. Activate mount
# Convert mount path to systemd unit name: /mnt/unas/media -> mnt-unas-media
SYSTEMD_UNIT=$(echo "$MOUNT_POINT" | sed 's|^/||;s|/$||;s|/|-|g')

# If using x-systemd.automount, activate the automount unit (mounts on first access, non-blocking).
# Otherwise fall back to a direct mount.
if echo "$MOUNT_OPTS" | grep -q "x-systemd.automount"; then
    echo "Activating automount for ${MOUNT_POINT}..."
    if sudo systemctl start "${SYSTEMD_UNIT}.automount" 2>/dev/null; then
        echo -e "${GREEN}Automount activated!${NC}"
        echo -e "The NFS share will connect on first access (e.g., ${YELLOW}ls ${MOUNT_POINT}${NC})."

        # Quick reachability check (don't block if NAS is unavailable)
        echo -e "Testing NAS reachability (5s timeout)..."
        if timeout 5 ping -c 1 "$NAS_SERVER" >/dev/null 2>&1; then
            echo -e "${GREEN}NAS is reachable at ${NAS_SERVER}${NC}"
            # Try to trigger the automount with a short timeout
            if timeout 10 ls "$MOUNT_POINT" >/dev/null 2>&1; then
                echo -e "${GREEN}Mount verified!${NC}"
                df -h "$MOUNT_POINT" | tail -1
            else
                echo -e "${YELLOW}NAS reachable but mount timed out — it may need a moment.${NC}"
                echo -e "Try: ${YELLOW}ls ${MOUNT_POINT}${NC}"
            fi
        else
            echo -e "${YELLOW}NAS not reachable right now — mount will connect when available.${NC}"
            echo -e "Check connectivity: ${YELLOW}ping ${NAS_SERVER}${NC}"
        fi
    else
        echo -e "${YELLOW}Could not start automount unit. Trying direct mount...${NC}"
        # Fall through to direct mount
        timeout 15 sudo mount "$MOUNT_POINT" && \
            echo -e "${GREEN}Successfully mounted!${NC}" && \
            df -h "$MOUNT_POINT" | tail -1 || \
            echo -e "${YELLOW}Direct mount timed out — NAS may not be reachable yet.${NC}"
    fi
else
    echo "Mounting ${MOUNT_POINT}..."
    if timeout 30 sudo mount "$MOUNT_POINT"; then
        echo -e "${GREEN}Successfully mounted!${NC}"
        df -h "$MOUNT_POINT" | tail -1
    else
        echo -e "${RED}Mount failed or timed out.${NC}"
        echo -e "Check your NAS is reachable: ${YELLOW}ping ${NAS_SERVER}${NC}"
        if [ "$PROTOCOL" = "nfs" ]; then
            echo -e "Verify NFS export: ${YELLOW}showmount -e ${NAS_SERVER}${NC}"
        fi
        echo -e "The fstab entry has been added — it will retry on next boot."
        echo -e "You can also retry manually: ${YELLOW}sudo mount ${MOUNT_POINT}${NC}"
        exit 1
    fi
fi

echo
echo -e "${GREEN}${BOLD}NAS mount configured!${NC}"
echo -e "  Mount persists across reboots via /etc/fstab."
echo -e "  With x-systemd.automount, the mount activates on first access."
echo -e "  To unmount: ${YELLOW}sudo umount ${MOUNT_POINT}${NC}"
echo -e "  To remove:  edit ${YELLOW}/etc/fstab${NC} and delete the homelab entry."
