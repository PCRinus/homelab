#!/bin/bash
# Minecraft Servers stop script
# Stops all server-specific compose files (skips common.compose.yml)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_DIR="${SCRIPT_DIR}/servers"
RESOLVED_ENV_FILE="${SCRIPT_DIR}/.generated-modrinth.env"
TEMP_ENV_FILE=""

usage() {
    cat <<'EOF'
Usage: ./stop.sh [server-name ...]

Stops all Minecraft servers by default.
If one or more server names are provided, stops only those servers.
EOF

    echo ""
    echo "Available servers (from servers/*.compose.yml):"
    list_server_names | sed 's/^/  - /'
    echo ""
    echo "Examples:"
    echo "  ./stop.sh"
    first_server="$(list_server_names | head -n1 || true)"
    if [[ -n "${first_server}" ]]; then
        echo "  ./stop.sh ${first_server}"
    fi
}

list_server_files() {
    if [[ ! -d "${SERVERS_DIR}" ]]; then
        return 0
    fi

    local f
    for f in "${SERVERS_DIR}"/*.compose.yml; do
        [[ -f "$f" ]] || continue
        printf '%s\n' "$(basename "$f")"
    done
}

list_server_names() {
    list_server_files | sed 's/\.compose\.yml$//'
}

cleanup() {
    if [[ -n "${TEMP_ENV_FILE}" && -f "${TEMP_ENV_FILE}" ]]; then
        rm -f "${TEMP_ENV_FILE}"
    fi
}
trap cleanup EXIT

cd "${SCRIPT_DIR}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

echo "🛑 Stopping Minecraft Servers..."

if [[ ! -d "${SERVERS_DIR}" ]]; then
    echo "❌ Missing servers directory: ${SERVERS_DIR}"
    exit 1
fi

SELECTED_FILES=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ "${arg}" == *.compose.yml ]]; then
            compose_file="${arg}"
        else
            compose_file="${arg}.compose.yml"
        fi

        if [[ ! -f "${SERVERS_DIR}/${compose_file}" ]]; then
            echo "❌ Unknown server '${arg}'. Expected one of:"
            list_server_names | sed 's/^/ - /'
            exit 1
        fi

        SELECTED_FILES+=("${compose_file}")
    done
else
    mapfile -t discovered_files < <(list_server_files)
    for f in "${discovered_files[@]}"; do
        SELECTED_FILES+=("$f")
    done
fi

if [[ ! -s "${RESOLVED_ENV_FILE}" ]]; then
    echo "⚠️  ${RESOLVED_ENV_FILE} not found. Using temporary placeholders for compose parsing."
    TEMP_ENV_FILE="$(mktemp)"
    cat >"${TEMP_ENV_FILE}" <<EOF
MODRINTH_PROJECTS_SURVIVAL_ISLAND=placeholder
MODRINTH_PROJECTS_WORLD_GENERATION=placeholder
EOF
    COMPOSE_ENV_ARGS=(--env-file ../.env --env-file "${TEMP_ENV_FILE}")
else
    COMPOSE_ENV_ARGS=(--env-file ../.env --env-file "${RESOLVED_ENV_FILE}")
fi

STOPPED=0
for compose_file in "${SELECTED_FILES[@]}"; do
    SERVER_NAME="${compose_file%.compose.yml}"
    PROJECT_NAME="minecraft-${SERVER_NAME}"
    SERVER_COMPOSE_FILE="${SERVERS_DIR}/${compose_file}"
    echo "🧹 Stopping ${SERVER_NAME}..."
    docker compose -p "${PROJECT_NAME}" "${COMPOSE_ENV_ARGS[@]}" -f common.compose.yml -f "${SERVER_COMPOSE_FILE}" down
    STOPPED=$((STOPPED + 1))
done

if [ "$STOPPED" -eq 0 ]; then
    echo "⚠️  No server compose files found"
else
    echo "✅ ${STOPPED} Minecraft server(s) stopped!"
fi
