#!/bin/bash
# Reconcile homelab services after boot without pulling or upgrading images.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
source "${SCRIPT_DIR}/lib/compose-env.sh"
source "${SCRIPT_DIR}/lib/host-readiness.sh"

ADGUARD_LAN_IP="${ADGUARD_LAN_IP:-192.168.1.166}"
NAS_CONTAINERS=(qbittorrent sonarr sonarr-anime radarr plex bazarr checkrr homepage)
MEDIA_SERVICES=(
    qbittorrent sonarr sonarr-anime radarr prowlarr flaresolverr seerr pulsarr
    plex bazarr tautulli plex-log-media-server plex-log-transcoder-statistics
    plex-log-scanner-matcher newt checkrr
)
NAS_MEDIA_SERVICES=(qbittorrent sonarr sonarr-anime radarr plex bazarr checkrr)

required_vars=(DOCKER_DATA MEDIA_PATH QBITTORRENT_INCOMPLETE_PATH DOCKER_SOCK)
for variable in "${required_vars[@]}"; do
    if [ -z "${!variable:-}" ]; then
        echo "Required environment variable ${variable} is not set" >&2
        exit 1
    fi
done

if [ ! -f "${REPO_DIR}/.env" ] && [ ! -f "${REPO_DIR}/.env.enc" ]; then
    echo "Neither ${REPO_DIR}/.env nor ${REPO_DIR}/.env.enc exists" >&2
    exit 1
fi

if [ -z "${DOCKER_HOST:-}" ]; then
    export DOCKER_HOST="unix://${DOCKER_SOCK}"
fi
export ADGUARD_LAN_IP

compose_up() {
    local stack="$1"
    shift

    echo "Reconciling ${stack}..."
    (
        cd "${REPO_DIR}/${stack}"
        homelab_compose up -d --no-build --pull never "$@"
    )
}

stop_nas_containers() {
    local running=()
    local container

    for container in "${NAS_CONTAINERS[@]}"; do
        if [ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" = "true" ]; then
            running+=("$container")
        fi
    done

    if [ "${#running[@]}" -gt 0 ]; then
        echo "Stopping NAS-dependent containers until the mount is safe: ${running[*]}"
        docker stop --time 15 "${running[@]}" >/dev/null
    fi
}

container_has_network_mount() {
    local container="$1"
    local target="$2"

    docker exec "$container" cat /proc/self/mountinfo 2>/dev/null \
        | awk -v target="$target" '
            $5 == target {
                for (i = 1; i <= NF; i++) {
                    if ($i == "-" && $(i + 1) ~ /^(nfs|nfs4|cifs|smb2|smb3)$/) found=1
                }
            }
            END { exit !found }
        '
}

repair_media_mounts() {
    local stale_services=()
    local service

    for service in "${NAS_MEDIA_SERVICES[@]}"; do
        if ! container_has_network_mount "$service" /data; then
            stale_services+=("$service")
        fi
    done

    if [ "${#stale_services[@]}" -gt 0 ]; then
        echo "Recreating containers with stale /data bind mounts: ${stale_services[*]}"
        (
            cd "${REPO_DIR}/media-server"
            homelab_compose up -d --no-build --pull never --force-recreate "${stale_services[@]}"
        )
    fi

    for service in "${NAS_MEDIA_SERVICES[@]}"; do
        if ! container_has_network_mount "$service" /data; then
            echo "${service} still does not have a network filesystem at /data" >&2
            return 1
        fi
    done
}

repair_homepage_mount() {
    if ! container_has_network_mount homepage /mnt/unas/media; then
        echo "Recreating Homepage with the active NAS mount"
        (
            cd "${REPO_DIR}/homepage"
            homelab_compose up -d --no-build --pull never --force-recreate homepage
        )
    fi

    if ! container_has_network_mount homepage /mnt/unas/media; then
        echo "Homepage still does not have a network filesystem at /mnt/unas/media" >&2
        return 1
    fi
}

adguard_wiring_ready() {
    [ "$(docker inspect --format '{{.State.Running}}' adguard 2>/dev/null || true)" = "true" ] \
        && [ -n "$(docker inspect --format '{{with index .NetworkSettings.Networks "media-net"}}{{.IPAddress}}{{end}}' adguard 2>/dev/null || true)" ] \
        && docker port adguard 53/tcp 2>/dev/null | grep -Fxq "${ADGUARD_LAN_IP}:53" \
        && docker port adguard 53/udp 2>/dev/null | grep -Fxq "${ADGUARD_LAN_IP}:53"
}

echo "Waiting for Docker..."
homelab_wait_for_docker
echo "Docker is ready"

# Stop affected containers as soon as Docker becomes available. Do not wait for
# DHCP first: that would give auto-restored containers time to use the empty
# directory underneath an inactive automount.
if ! homelab_is_network_fs_type "$(homelab_network_fs_type "$MEDIA_PATH")"; then
    stop_nas_containers
fi

echo "Waiting for LAN address ${ADGUARD_LAN_IP}..."
homelab_wait_for_ipv4 "$ADGUARD_LAN_IP"
echo "LAN address is ready"

if ! homelab_media_mount_ready "$MEDIA_PATH"; then
    homelab_recover_media_mount "$MEDIA_PATH"
fi

if ! homelab_media_mount_ready "$MEDIA_PATH"; then
    echo "Refusing to start NAS-dependent services without a real network mount" >&2
    exit 1
fi

if [ ! -d "$QBITTORRENT_INCOMPLETE_PATH" ]; then
    echo "Local qBittorrent staging path is missing: ${QBITTORRENT_INCOMPLETE_PATH}" >&2
    echo "Run scripts/init.sh as the homelab user so it is created with the correct ownership" >&2
    exit 1
fi

compose_up media-server "${MEDIA_SERVICES[@]}"
repair_media_mounts

compose_up adguard adguard
if ! adguard_wiring_ready; then
    echo "Recreating AdGuard to repair its LAN port and media-net attachment"
    (
        cd "${REPO_DIR}/adguard"
        homelab_compose up -d --no-build --pull never --force-recreate adguard
    )
fi
if ! adguard_wiring_ready; then
    echo "AdGuard is still missing its expected LAN port or media-net attachment" >&2
    exit 1
fi

compose_up monitoring
compose_up homepage homepage
repair_homepage_mount
compose_up home-assistant
compose_up cloudflare-tunnel

echo "Homelab boot reconciliation completed successfully"
