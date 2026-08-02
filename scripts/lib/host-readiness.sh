#!/bin/bash

# Shared host-readiness checks used by interactive startup and boot recovery.

homelab_network_fs_type() {
    local path="$1"

    findmnt --target "$path" --noheadings --raw --output FSTYPE 2>/dev/null \
        | awk '$1 ~ /^(nfs|nfs4|cifs|smb2|smb3)$/ { type=$1 } END { print type }'
}

homelab_is_network_fs_type() {
    case "$1" in
        nfs|nfs4|cifs|smb2|smb3)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

homelab_media_mount_ready() {
    local path="$1"
    local probe_timeout="${HOMELAB_MOUNT_PROBE_TIMEOUT:-20}"
    local fs_type

    [ -d "$path" ] || return 1

    # Accessing the directory activates an x-systemd.automount mount. A plain
    # mountpoint check is insufficient because autofs itself looks mounted.
    timeout "$probe_timeout" ls -U "$path" >/dev/null 2>&1 || return 1
    fs_type="$(homelab_network_fs_type "$path")"
    homelab_is_network_fs_type "$fs_type"
}

homelab_systemctl() {
    if [ "${EUID}" -eq 0 ]; then
        systemctl "$@"
    else
        sudo systemctl "$@"
    fi
}

homelab_mount_unit_name() {
    local path="$1"

    if command -v systemd-escape >/dev/null 2>&1; then
        systemd-escape --path "$path"
    else
        printf '%s\n' "${path#/}" | sed 's|/$||;s|/|-|g'
    fi
}

homelab_recover_media_mount() {
    local path="$1"
    local unit_name

    if homelab_media_mount_ready "$path"; then
        return 0
    fi

    if ! command -v systemctl >/dev/null 2>&1; then
        echo "Cannot recover ${path}: systemctl is not available" >&2
        return 1
    fi

    unit_name="$(homelab_mount_unit_name "$path")"
    echo "Recovering NAS mount ${path}..."

    # A burst of accesses before the LAN is ready can put the generated mount
    # unit into mount-start-limit-hit. Clear both generated units before retrying.
    homelab_systemctl reset-failed "${unit_name}.mount" "${unit_name}.automount" 2>/dev/null || true

    if homelab_systemctl list-unit-files "${unit_name}.automount" --no-legend 2>/dev/null \
        | grep -q "^${unit_name}\.automount"; then
        homelab_systemctl restart "${unit_name}.automount"
    else
        homelab_systemctl restart "${unit_name}.mount" 2>/dev/null \
            || homelab_systemctl start "${unit_name}.mount"
    fi

    if ! homelab_media_mount_ready "$path"; then
        echo "NAS mount ${path} is not backed by NFS or CIFS after recovery" >&2
        return 1
    fi

    echo "NAS mount ${path} is active ($(homelab_network_fs_type "$path"))"
}

homelab_ipv4_is_assigned() {
    local expected_ip="$1"

    ip -4 -o address show 2>/dev/null \
        | awk -v expected="$expected_ip" '{ split($4, address, "/"); if (address[1] == expected) found=1 } END { exit !found }'
}

homelab_wait_for_ipv4() {
    local expected_ip="$1"
    local wait_seconds="${2:-${HOMELAB_NETWORK_WAIT_SECONDS:-120}}"
    local deadline=$((SECONDS + wait_seconds))

    while ! homelab_ipv4_is_assigned "$expected_ip"; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "Timed out waiting for LAN address ${expected_ip}" >&2
            return 1
        fi
        sleep 2
    done
}

homelab_wait_for_docker() {
    local wait_seconds="${1:-${HOMELAB_DOCKER_WAIT_SECONDS:-120}}"
    local deadline=$((SECONDS + wait_seconds))

    while ! docker info >/dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "Timed out waiting for Docker" >&2
            return 1
        fi
        sleep 2
    done
}
