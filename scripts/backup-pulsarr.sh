#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MEDIA_SERVER_DIR="${REPO_DIR}/media-server"
source "${SCRIPT_DIR}/lib/compose-env.sh"

if [ -f "$HOME/.zshenv" ]; then
    source "$HOME/.zshenv"
fi

BACKUP_MOUNT_PATH="${BACKUP_MOUNT_PATH:-/mnt/unas/container-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
DOCKER_DATA_PATH="${DOCKER_DATA:-$HOME/docker}"
BACKUP_DIR="${BACKUP_MOUNT_PATH}/pulsarr"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE_PATH="${BACKUP_DIR}/pulsarr-config-${TIMESTAMP}.tar.gz"
CHECKSUM_PATH="${ARCHIVE_PATH}.sha256"

CONFIG_DIR="${DOCKER_DATA_PATH}/pulsarr"

if [ ! -d "$CONFIG_DIR" ]; then
    echo "Pulsarr config directory not found: ${CONFIG_DIR}"
    exit 1
fi

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

cd "$MEDIA_SERVER_DIR"
if ! homelab_compose config --services 2>/dev/null | grep -qx "pulsarr"; then
    echo "Could not find pulsarr service in media-server compose."
    exit 1
fi

STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir -p "$STAGING_DIR/pulsarr/db"

# Only the database is backed up; logs are not needed for a restore.
if homelab_compose ps --status running --services 2>/dev/null | grep -qx "pulsarr"; then
    # Online snapshot so the watchlist workflow keeps running. The image runs
    # Bun, so use bun:sqlite; VACUUM INTO writes a consistent, self-contained copy.
    CONTAINER_SNAPSHOT="/tmp/pulsarr-backup.db"
    echo "Snapshotting live pulsarr database..."
    homelab_compose exec -T pulsarr rm -f "$CONTAINER_SNAPSHOT"
    homelab_compose exec -T pulsarr bun -e '
const { Database } = require("bun:sqlite");
const db = new Database("/app/data/db/pulsarr.db", { readonly: true });
db.run("VACUUM INTO ?", [process.argv[1]]);
db.close();
' "$CONTAINER_SNAPSHOT"
    homelab_compose cp "pulsarr:${CONTAINER_SNAPSHOT}" "$STAGING_DIR/pulsarr/db/pulsarr.db" > /dev/null
    homelab_compose exec -T pulsarr rm -f "$CONTAINER_SNAPSHOT"
else
    echo "pulsarr is not running; copying database files directly..."
    cp -p "$CONFIG_DIR"/db/pulsarr.db* "$STAGING_DIR/pulsarr/db/"
fi

echo "Creating backup archive: $ARCHIVE_PATH"
tar -C "$STAGING_DIR" -czf "$ARCHIVE_PATH" "pulsarr"
sha256sum "$ARCHIVE_PATH" > "$CHECKSUM_PATH"

echo "Backup created successfully."
echo "Archive: $ARCHIVE_PATH"
echo "Checksum: $CHECKSUM_PATH"

echo "Applying retention policy: ${BACKUP_RETENTION_DAYS} days"
find "$BACKUP_DIR" -type f -name 'pulsarr-config-*.tar.gz' -mtime +"$BACKUP_RETENTION_DAYS" -delete
find "$BACKUP_DIR" -type f -name 'pulsarr-config-*.tar.gz.sha256' -mtime +"$BACKUP_RETENTION_DAYS" -delete

echo "Done."
