#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MEDIA_SERVER_DIR="${REPO_DIR}/media-server"

if [ -f "$HOME/.zshenv" ]; then
    source "$HOME/.zshenv"
fi

BACKUP_MOUNT_PATH="${BACKUP_MOUNT_PATH:-/mnt/unas/container-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
DOCKER_DATA_PATH="${DOCKER_DATA:-$HOME/docker}"
BACKUP_DIR="${BACKUP_MOUNT_PATH}/seerr"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="${BACKUP_DIR}/seerr-config-${TIMESTAMP}.tar.gz"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

CONFIG_DIR="${DOCKER_DATA_PATH}/seerr"
if [ ! -d "$CONFIG_DIR" ]; then
    CONFIG_DIR="${DOCKER_DATA_PATH}/overseerr"
fi

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Seerr config directory not found. Expected one of:"
    echo "  - ${DOCKER_DATA_PATH}/seerr"
    echo "  - ${DOCKER_DATA_PATH}/overseerr"
    exit 1
fi

CONFIG_NAME="$(basename "$CONFIG_DIR")"

if [ ! -d "$BACKUP_MOUNT_PATH" ]; then
    echo "Backup mount path does not exist: $BACKUP_MOUNT_PATH"
    exit 1
fi

ls "$BACKUP_MOUNT_PATH" > /dev/null 2>&1 || true
if ! mountpoint -q "$BACKUP_MOUNT_PATH"; then
    echo "Backup path is not a mounted filesystem: $BACKUP_MOUNT_PATH"
    echo "Refusing to write backup to local disk."
    exit 1
fi

mkdir -p "$BACKUP_DIR"

if [ -n "${DOCKER_SOCK:-}" ] && [ -z "${DOCKER_HOST:-}" ]; then
    export DOCKER_HOST="unix://${DOCKER_SOCK}"
fi

if ! command -v docker > /dev/null 2>&1; then
    echo "Docker CLI not found."
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    echo "Docker daemon is not reachable."
    exit 1
fi

SERVICE_NAME=""
cd "$MEDIA_SERVER_DIR"
if docker compose config --services 2>/dev/null | grep -qx "seerr"; then
    SERVICE_NAME="seerr"
elif docker compose config --services 2>/dev/null | grep -qx "overseerr"; then
    SERVICE_NAME="overseerr"
else
    echo "Could not find seerr/overseerr service in media-server compose."
    exit 1
fi

was_running=false
if docker compose ps --status running --services 2>/dev/null | grep -qx "$SERVICE_NAME"; then
    was_running=true
fi

restore_service() {
    if [ "$was_running" = true ]; then
        docker compose start "$SERVICE_NAME" > /dev/null 2>&1 || true
    fi
}
trap restore_service EXIT

if [ "$was_running" = true ]; then
    echo "Stopping ${SERVICE_NAME} for consistent backup..."
    docker compose stop "$SERVICE_NAME"
fi

echo "Creating backup archive: $ARCHIVE_PATH"
tar -C "$DOCKER_DATA_PATH" -czf "$ARCHIVE_PATH" "$CONFIG_NAME"
sha256sum "$ARCHIVE_PATH" > "$CHECKSUM_PATH"

echo "Backup created successfully."
echo "Archive: $ARCHIVE_PATH"
echo "Checksum: $CHECKSUM_PATH"

echo "Applying retention policy: ${BACKUP_RETENTION_DAYS} days"
find "$BACKUP_DIR" -type f -name 'seerr-config-*.tar.gz' -mtime +"$BACKUP_RETENTION_DAYS" -delete
find "$BACKUP_DIR" -type f -name 'seerr-config-*.tar.gz.sha256' -mtime +"$BACKUP_RETENTION_DAYS" -delete

echo "Done."
