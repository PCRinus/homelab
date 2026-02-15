#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS_DIR="${SCRIPT_DIR}/mods"
OUTPUT_FILE="${SCRIPT_DIR}/.generated-modrinth.env"
LOADER="fabric"
MC_VERSION="${MC_VERSION:-}"

usage() {
  cat <<'EOF'
Usage: ./resolve-modrinth-mods.sh [--mc-version <version>] [--loader <loader>] [--output <file>]

Resolves and validates Modrinth mod versions for the selected Minecraft version.
Writes Docker Compose env vars to .generated-modrinth.env by default.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mc-version)
      MC_VERSION="$2"
      shift 2
      ;;
    --loader)
      LOADER="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd jq

if [[ -z "${MC_VERSION}" ]]; then
  MC_VERSION="$(grep -E '^[[:space:]]*VERSION:' "${SCRIPT_DIR}/common.compose.yml" | head -n1 | sed -E 's/.*:-([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
fi

if [[ -z "${MC_VERSION}" ]]; then
  echo "Could not determine Minecraft version. Pass --mc-version explicitly." >&2
  exit 1
fi

read_mod_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi

  awk '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 == "" || $0 ~ /^#/) next
      print $0
    }
  ' "$file"
}

dedupe_list() {
  awk '!seen[$0]++'
}

resolve_mod() {
  local project_slug="$1"
  local response version_id

  response="$(curl --silent --show-error --fail --get \
    --data-urlencode "loaders=[\"${LOADER}\"]" \
    --data-urlencode "game_versions=[\"${MC_VERSION}\"]" \
    "https://api.modrinth.com/v2/project/${project_slug}/version")"

  version_id="$(jq -r '.[0].id // empty' <<<"${response}")"

  if [[ -z "${version_id}" ]]; then
    return 1
  fi

  printf '%s:%s\n' "${project_slug}" "${version_id}"
}

resolve_group() {
  local name="$1"
  shift
  local files=("$@")

  local raw_mods=()
  local file

  for file in "${files[@]}"; do
    if [[ -f "${file}" ]]; then
      while IFS= read -r mod; do
        raw_mods+=("${mod}")
      done < <(read_mod_file "${file}")
    fi
  done

  mapfile -t mods < <(printf '%s\n' "${raw_mods[@]:-}" | sed '/^$/d' | dedupe_list)

  local resolved=()
  local unresolved=()
  local mod

  echo "🔎 Resolving ${name} mods for Minecraft ${MC_VERSION} (${LOADER})..." >&2
  for mod in "${mods[@]}"; do
    if resolved_ref="$(resolve_mod "${mod}")"; then
      resolved+=("${resolved_ref}")
      echo "  ✅ ${mod}" >&2
    else
      unresolved+=("${mod}")
      echo "  ❌ ${mod} (no compatible version found)" >&2
    fi
  done

  if [[ ${#unresolved[@]} -gt 0 ]]; then
    echo "" >&2
    echo "Failed to resolve compatible versions for ${name}:" >&2
    printf ' - %s\n' "${unresolved[@]}" >&2
    return 1
  fi

  local joined
  joined="$(printf '%s,' "${resolved[@]}")"
  joined="${joined%,}"

  printf '%s\n' "${joined}"
}

COMMON_MODS="$(resolve_group "common" "${MODS_DIR}/performance.txt" "${MODS_DIR}/content.txt")"
WORLD_GEN_MODS="$(resolve_group "world-generation" "${MODS_DIR}/performance.txt" "${MODS_DIR}/content.txt" "${MODS_DIR}/world-generation-extra.txt")"

cat >"${OUTPUT_FILE}" <<EOF
GENERATED_MC_VERSION='${MC_VERSION}'
MODRINTH_PROJECTS_SURVIVAL_ISLAND='${COMMON_MODS}'
MODRINTH_PROJECTS_WORLD_GENERATION='${WORLD_GEN_MODS}'
EOF

echo ""
echo "✅ Wrote resolved mod lists to ${OUTPUT_FILE}"
