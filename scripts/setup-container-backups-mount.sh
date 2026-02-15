#!/bin/bash
# Configure NAS mount for container backups.
#
# Usage:
#   ./scripts/setup-container-backups-mount.sh
#   ./scripts/setup-container-backups-mount.sh /mnt/unas/container-backups
#   ./scripts/setup-container-backups-mount.sh /mnt/unas/container-backups 192.168.1.10 nfs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_POINT="${1:-/mnt/unas/container-backups}"
NAS_SERVER="${2:-}"
PROTOCOL="${3:-nfs}"

export NAS_SETUP_DEFAULT_MOUNT_POINT="$MOUNT_POINT"
export NAS_SETUP_DEFAULT_SHARE="ContainerBackups"
export NAS_SETUP_DEFAULT_PROTOCOL="$PROTOCOL"

if [ -n "$NAS_SERVER" ]; then
    export NAS_SETUP_DEFAULT_SERVER="$NAS_SERVER"
fi

"${SCRIPT_DIR}/setup-nas-mount.sh" "$MOUNT_POINT"
