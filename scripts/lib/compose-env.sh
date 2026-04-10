#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PLAIN_ENV_FILE="${REPO_DIR}/.env"
ENCRYPTED_ENV_FILE="${PLAIN_ENV_FILE}.enc"

resolve_homelab_runtime_env_file() {
    if [ -f "$PLAIN_ENV_FILE" ]; then
        printf '%s\n' "$PLAIN_ENV_FILE"
        return 0
    fi

    if [ ! -f "$ENCRYPTED_ENV_FILE" ]; then
        echo "Missing ${PLAIN_ENV_FILE} and ${ENCRYPTED_ENV_FILE}" >&2
        return 1
    fi

    if ! command -v sops > /dev/null 2>&1; then
        echo "sops is required to decrypt ${ENCRYPTED_ENV_FILE}" >&2
        return 1
    fi

    if ! command -v age > /dev/null 2>&1; then
        echo "age is required to decrypt ${ENCRYPTED_ENV_FILE}" >&2
        return 1
    fi

    local age_key_file
    age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
    if [ ! -f "$age_key_file" ]; then
        echo "Age private key not found at ${age_key_file}" >&2
        return 1
    fi

    local runtime_env_file
    runtime_env_file="$(mktemp "${TMPDIR:-/tmp}/homelab-env.XXXXXX")"
    export SOPS_AGE_KEY_FILE="$age_key_file"
    if ! sops --decrypt --input-type dotenv --output-type dotenv "$ENCRYPTED_ENV_FILE" > "$runtime_env_file"; then
        rm -f "$runtime_env_file"
        return 1
    fi
    chmod 600 "$runtime_env_file"
    printf '%s\n' "$runtime_env_file"
}

homelab_compose() {
    local runtime_env_file
    local temp_env_file=""
    local status

    runtime_env_file="$(resolve_homelab_runtime_env_file)" || return 1
    if [ "$runtime_env_file" != "$PLAIN_ENV_FILE" ]; then
        temp_env_file="$runtime_env_file"
    fi

    export HOMELAB_RUNTIME_ENV_FILE="$runtime_env_file"
    if docker compose --env-file "$runtime_env_file" "$@"; then
        status=0
    else
        status=$?
    fi

    if [ -n "$temp_env_file" ] && [ -f "$temp_env_file" ]; then
        rm -f "$temp_env_file"
    fi

    return $status
}