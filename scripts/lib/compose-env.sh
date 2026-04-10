#!/bin/bash

HOMELAB_COMPOSE_ENV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_COMPOSE_ENV_REPO_DIR="$(dirname "$(dirname "$HOMELAB_COMPOSE_ENV_LIB_DIR")")"
HOMELAB_PLAIN_ENV_FILE="${HOMELAB_COMPOSE_ENV_REPO_DIR}/.env"
HOMELAB_ENCRYPTED_ENV_FILE="${HOMELAB_PLAIN_ENV_FILE}.enc"

resolve_homelab_runtime_env_file() {
    if [ -f "$HOMELAB_ENCRYPTED_ENV_FILE" ]; then
        if ! command -v sops > /dev/null 2>&1; then
            echo "sops is required to decrypt ${HOMELAB_ENCRYPTED_ENV_FILE}" >&2
            return 1
        fi

        if ! command -v age > /dev/null 2>&1; then
            echo "age is required to decrypt ${HOMELAB_ENCRYPTED_ENV_FILE}" >&2
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
        if ! sops --decrypt --input-type dotenv --output-type dotenv "$HOMELAB_ENCRYPTED_ENV_FILE" > "$runtime_env_file"; then
            rm -f "$runtime_env_file"
            return 1
        fi
        chmod 600 "$runtime_env_file"
        printf '%s\n' "$runtime_env_file"
        return 0
    fi

    if [ -f "$HOMELAB_PLAIN_ENV_FILE" ]; then
        printf '%s\n' "$HOMELAB_PLAIN_ENV_FILE"
        return 0
    fi

    echo "Missing ${HOMELAB_PLAIN_ENV_FILE} and ${HOMELAB_ENCRYPTED_ENV_FILE}" >&2
    return 1
}

homelab_compose() {
    local runtime_env_file
    local temp_env_file=""
    local status

    runtime_env_file="$(resolve_homelab_runtime_env_file)" || return 1
    if [ "$runtime_env_file" != "$HOMELAB_PLAIN_ENV_FILE" ]; then
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