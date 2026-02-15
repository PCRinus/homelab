#!/bin/bash
# Minecraft Servers startup script
# Starts all server-specific compose files (skips common.compose.yml)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_DIR="${SCRIPT_DIR}/servers"
RESOLVER_SCRIPT="${SCRIPT_DIR}/resolve-modrinth-mods.sh"
RESOLVED_ENV_FILE="${SCRIPT_DIR}/.generated-modrinth.env"

usage() {
        cat <<'EOF'
Usage: ./start.sh [server-name ...]

Starts all Minecraft servers by default.
If one or more server names are provided, starts only those servers.
EOF

    echo ""
    echo "Available servers (from *.compose.yml):"
    list_server_names | sed 's/^/  - /'
    echo ""
    echo "Examples:"
    echo "  ./start.sh"
    first_server="$(list_server_names | head -n1 || true)"
    if [[ -n "${first_server}" ]]; then
        echo "  ./start.sh ${first_server}"
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

detect_target_mc_version() {
    if [[ -n "${MC_VERSION:-}" ]]; then
        printf '%s\n' "${MC_VERSION}"
        return 0
    fi

    grep -E '^[[:space:]]*VERSION:' "${SCRIPT_DIR}/common.compose.yml" | head -n1 | sed -E 's/.*:-([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

extract_env_value() {
    local key="$1"
    local file="$2"
    local raw
    raw="$(grep -E "^${key}=" "$file" | head -n1 | cut -d= -f2- || true)"
    raw="${raw%\'}"
    raw="${raw#\'}"
    printf '%s\n' "${raw}"
}

cd "${SCRIPT_DIR}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

echo "🎮 Starting Minecraft Servers..."

if [[ ! -d "${SERVERS_DIR}" ]]; then
    echo "❌ Missing servers directory: ${SERVERS_DIR}"
    exit 1
fi

SELECTED_FILES=()
if [[ $# -gt 0 ]]; then
    for arg in "$@"; do
        if [[ "${arg}" == *.compose.yml ]]; then
            compose_file="${arg}"
            server_name="${arg%.compose.yml}"
        else
            compose_file="${arg}.compose.yml"
            server_name="${arg}"
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

if [[ ! -x "${RESOLVER_SCRIPT}" ]]; then
    chmod +x "${RESOLVER_SCRIPT}"
fi

TARGET_MC_VERSION="$(detect_target_mc_version)"
if [[ -z "${TARGET_MC_VERSION}" ]]; then
    echo "❌ Could not determine target Minecraft version"
    exit 1
fi

NEEDS_RESOLVE="true"
if [[ -s "${RESOLVED_ENV_FILE}" ]]; then
    CACHED_MC_VERSION="$(extract_env_value "GENERATED_MC_VERSION" "${RESOLVED_ENV_FILE}")"
    HAS_SURVIVAL_VAR="$(grep -E '^MODRINTH_PROJECTS_SURVIVAL_ISLAND=' "${RESOLVED_ENV_FILE}" || true)"
    HAS_WORLD_VAR="$(grep -E '^MODRINTH_PROJECTS_WORLD_GENERATION=' "${RESOLVED_ENV_FILE}" || true)"

    if [[ "${CACHED_MC_VERSION}" == "${TARGET_MC_VERSION}" && -n "${HAS_SURVIVAL_VAR}" && -n "${HAS_WORLD_VAR}" ]]; then
        NEEDS_RESOLVE="false"
    fi
fi

if [[ "${NEEDS_RESOLVE}" == "true" ]]; then
    echo "🧩 Resolving Modrinth mods for VERSION=${TARGET_MC_VERSION}..."
    "${RESOLVER_SCRIPT}" --mc-version "${TARGET_MC_VERSION}" --output "${RESOLVED_ENV_FILE}"
else
    echo "🧩 Reusing cached compatible mod list for VERSION=${TARGET_MC_VERSION}"
fi

if [[ ! -s "${RESOLVED_ENV_FILE}" ]]; then
    echo "❌ ${RESOLVED_ENV_FILE} is missing or empty"
    exit 1
fi

COMPOSE_ENV_ARGS=(--env-file ../.env --env-file "${RESOLVED_ENV_FILE}")

STARTED=0
for f in "${SELECTED_FILES[@]}"; do
    SERVER_NAME="${f%.compose.yml}"
    PROJECT_NAME="minecraft-${SERVER_NAME}"
    SERVER_COMPOSE_FILE="${SERVERS_DIR}/${f}"
    echo "📦 Pulling ${SERVER_NAME}..."
    docker compose -p "${PROJECT_NAME}" "${COMPOSE_ENV_ARGS[@]}" -f common.compose.yml -f "${SERVER_COMPOSE_FILE}" pull
    echo "🚀 Starting ${SERVER_NAME}..."
    docker compose -p "${PROJECT_NAME}" "${COMPOSE_ENV_ARGS[@]}" -f common.compose.yml -f "${SERVER_COMPOSE_FILE}" up -d
    STARTED=$((STARTED + 1))
done

if [ "$STARTED" -eq 0 ]; then
    echo "⚠️  No server compose files found"
else
    echo "✅ ${STARTED} Minecraft server(s) started!"
fi
