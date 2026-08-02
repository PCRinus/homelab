#!/bin/bash
# Install and enable the boot reconciliation service and NAS unit hardening.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SYSTEMD_SOURCE_DIR="${REPO_DIR}/systemd"
ENV_DEST="/etc/homelab/homelab-reconcile.env"
SERVICE_DEST="/etc/systemd/system/homelab-reconcile.service"

if [ "$(uname -s)" != "Linux" ] || ! command -v systemctl >/dev/null 2>&1; then
    echo "This installer must be run on the Linux homelab host" >&2
    exit 1
fi

required_vars=(DOCKER_DATA MEDIA_PATH QBITTORRENT_INCOMPLETE_PATH DOCKER_SOCK)
for variable in "${required_vars[@]}"; do
    if [ -z "${!variable:-}" ]; then
        echo "Required environment variable ${variable} is not set" >&2
        echo "Load the host configuration first (for example: source ~/.zshenv)" >&2
        exit 1
    fi
done

for value in "$REPO_DIR" "$DOCKER_DATA" "$MEDIA_PATH" "$QBITTORRENT_INCOMPLETE_PATH" "$DOCKER_SOCK"; do
    if [[ "$value" == *$'\n'* ]]; then
        echo "Paths containing newlines are not supported" >&2
        exit 1
    fi
done

quote_systemd_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

install_user="${SUDO_USER:-${USER:-$(id -un)}}"
install_home="$(getent passwd "$install_user" | cut -d: -f6)"
if [ -z "$install_home" ]; then
    echo "Could not determine the home directory for ${install_user}" >&2
    exit 1
fi

mount_unit="$(systemd-escape --path "$MEDIA_PATH")"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

{
    printf 'HOMELAB_REPO_DIR=%s\n' "$(quote_systemd_value "$REPO_DIR")"
    printf 'HOME=%s\n' "$(quote_systemd_value "$install_home")"
    printf 'DOCKER_DATA=%s\n' "$(quote_systemd_value "$DOCKER_DATA")"
    printf 'MEDIA_PATH=%s\n' "$(quote_systemd_value "$MEDIA_PATH")"
    printf 'QBITTORRENT_INCOMPLETE_PATH=%s\n' "$(quote_systemd_value "$QBITTORRENT_INCOMPLETE_PATH")"
    printf 'DOCKER_SOCK=%s\n' "$(quote_systemd_value "$DOCKER_SOCK")"
    printf 'DOCKER_GID=%s\n' "$(quote_systemd_value "${DOCKER_GID:-}")"
    printf 'RENDER_GID=%s\n' "$(quote_systemd_value "${RENDER_GID:-}")"
    printf 'ADGUARD_LAN_IP=%s\n' "$(quote_systemd_value "${ADGUARD_LAN_IP:-192.168.1.166}")"
    printf 'SOPS_AGE_KEY_FILE=%s\n' "$(quote_systemd_value "${SOPS_AGE_KEY_FILE:-${install_home}/.config/sops/age/keys.txt}")"
} > "${temp_dir}/homelab-reconcile.env"

echo "Installing homelab-reconcile.service..."
sudo install -d -m 0755 /etc/homelab
sudo install -m 0644 "${temp_dir}/homelab-reconcile.env" "$ENV_DEST"
sudo install -m 0644 "${SYSTEMD_SOURCE_DIR}/homelab-reconcile.service" "$SERVICE_DEST"

echo "Installing start-limit hardening for ${mount_unit}.mount and .automount..."
for suffix in mount automount; do
    dropin_dir="/etc/systemd/system/${mount_unit}.${suffix}.d"
    sudo install -d -m 0755 "$dropin_dir"
    sudo install -m 0644 "${SYSTEMD_SOURCE_DIR}/nas-mount-unit.d/override.conf" "${dropin_dir}/override.conf"
done

sudo systemctl daemon-reload
sudo systemctl enable --now homelab-reconcile.service

echo
echo "Boot reconciliation is installed and enabled."
echo "Check it with: sudo systemctl status homelab-reconcile.service"
echo "Follow logs with: sudo journalctl -u homelab-reconcile.service -f"
