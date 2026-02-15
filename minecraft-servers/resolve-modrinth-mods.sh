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

declare -A RESOLVED_BY_SLUG=()
declare -A SLUG_BY_PROJECT_ID=()

fetch_versions_for_project() {
  local project_ref="$1"

  curl --silent --show-error --fail --get \
    --data-urlencode "loaders=[\"${LOADER}\"]" \
    --data-urlencode "game_versions=[\"${MC_VERSION}\"]" \
    "https://api.modrinth.com/v2/project/${project_ref}/version"
}

get_slug_for_project_id() {
  local project_id="$1"

  if [[ -n "${SLUG_BY_PROJECT_ID[${project_id}]:-}" ]]; then
    printf '%s\n' "${SLUG_BY_PROJECT_ID[${project_id}]}"
    return 0
  fi

  local project_response slug
  project_response="$(curl --silent --show-error --fail "https://api.modrinth.com/v2/project/${project_id}")"
  slug="$(jq -r '.slug // empty' <<<"${project_response}")"

  if [[ -z "${slug}" ]]; then
    return 1
  fi

  SLUG_BY_PROJECT_ID["${project_id}"]="${slug}"
  printf '%s\n' "${slug}"
}

resolve_mod() {
  local project_slug="$1"

  if [[ -n "${RESOLVED_BY_SLUG[${project_slug}]:-}" ]]; then
    return 0
  fi

  local versions_response version_json version_id
  versions_response="$(fetch_versions_for_project "${project_slug}")"
  version_json="$(jq -c '.[0] // empty' <<<"${versions_response}")"
  version_id="$(jq -r '.id // empty' <<<"${version_json}")"

  if [[ -z "${version_id}" ]]; then
    return 1
  fi

  RESOLVED_BY_SLUG["${project_slug}"]="${version_id}"

  local dep_project_id dep_slug dep_type dep_version_id dep_versions_response dep_version_json
  while IFS=$'\t' read -r dep_project_id dep_type dep_version_id; do
    [[ -n "${dep_project_id}" ]] || continue

    if [[ "${dep_type}" != "required" ]]; then
      continue
    fi

    dep_slug="$(get_slug_for_project_id "${dep_project_id}")" || continue

    if [[ -n "${dep_version_id}" ]]; then
      dep_versions_response="$(fetch_versions_for_project "${dep_slug}")"
      dep_version_json="$(jq -c --arg id "${dep_version_id}" 'map(select(.id == $id)) | .[0] // empty' <<<"${dep_versions_response}")"

      if [[ -n "${dep_version_json}" ]]; then
        RESOLVED_BY_SLUG["${dep_slug}"]="${dep_version_id}"
      fi
    fi

    resolve_mod "${dep_slug}" || true
  done < <(jq -r '.dependencies[]? | [.project_id, .dependency_type, (.version_id // "")] | @tsv' <<<"${version_json}")

  return 0
}

print_resolved_list() {
  local key
  for key in "${!RESOLVED_BY_SLUG[@]}"; do
    printf '%s:%s\n' "${key}" "${RESOLVED_BY_SLUG[${key}]}"
  done | sort
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

  local unresolved=()
  local mod

  RESOLVED_BY_SLUG=()
  SLUG_BY_PROJECT_ID=()

  echo "🔎 Resolving ${name} mods for Minecraft ${MC_VERSION} (${LOADER})..." >&2
  for mod in "${mods[@]}"; do
    if resolve_mod "${mod}"; then
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
  mapfile -t resolved < <(print_resolved_list)
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
