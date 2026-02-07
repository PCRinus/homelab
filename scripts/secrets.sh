#!/bin/bash
# ===========================================
# Secrets Management (sops + age)
# ===========================================
# Encrypt and decrypt secret files for this homelab repo.
#
# Structured files (.env, .yaml, .yml, .tfvars) are encrypted
# with sops (value-level encryption, keys remain visible).
# Unstructured files (tunnel-token, wg0.conf) are encrypted
# with raw age (entire file encrypted).
#
# Usage:
#   ./scripts/secrets.sh encrypt   # Encrypt all secret files → .enc variants
#   ./scripts/secrets.sh decrypt   # Decrypt .enc files → plaintext originals
#   ./scripts/secrets.sh status    # Show which files are encrypted/decrypted
#
# Prerequisites:
#   - sops (https://github.com/getsops/sops)
#   - age  (https://github.com/FiloSottile/age)
#   - Age private key at ~/.config/sops/age/keys.txt
# ===========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Age public key (must match .sops.yaml)
AGE_PUBLIC_KEY="age13przqengtm203ntnckywpztfh7h700pglqn44ggukjpw98usd9ws4vks4c"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# --- File definitions ---
# Structured files: encrypted by sops (value-level encryption)
# Format: "path:type" where type is the sops input type (dotenv, yaml, json)
# sops can't auto-detect type from .enc extensions, so we specify explicitly.
SOPS_FILES=(
    ".env:dotenv"
    "cloudflare-tunnel/terraform.tfvars:dotenv"
    "home-assistant/secrets.yaml:yaml"
    "media-server/buildarr/buildarr-secrets.yml:yaml"
    "media-server/configarr/secrets.yml:yaml"
)

# Unstructured files: encrypted by age (whole-file encryption)
AGE_FILES=(
    "cloudflare-tunnel/tunnel-token"
    "media-server/wg0.conf"
)

# ===========================================
# Preflight checks
# ===========================================
check_tools() {
    local missing=()
    command -v sops >/dev/null 2>&1 || missing+=("sops")
    command -v age >/dev/null 2>&1  || missing+=("age")

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo "Install them:"
        echo "  age:  sudo apt install age  (or https://github.com/FiloSottile/age/releases)"
        echo "  sops: https://github.com/getsops/sops/releases"
        exit 1
    fi
}

check_age_key() {
    if [ ! -f "$AGE_KEY_FILE" ]; then
        echo -e "${RED}Age private key not found at ${AGE_KEY_FILE}${NC}"
        echo "Generate one with:  age-keygen -o \"\$HOME/.config/sops/age/keys.txt\""
        echo "Or copy your existing key from the old machine."
        exit 1
    fi
}

# ===========================================
# Encrypt
# ===========================================
do_encrypt() {
    check_tools
    check_age_key

    echo -e "${BOLD}Encrypting secrets...${NC}"
    echo
    local count=0

    # Structured files via sops
    for entry in "${SOPS_FILES[@]}"; do
        file="${entry%%:*}"
        ftype="${entry##*:}"
        src="${REPO_DIR}/${file}"
        dst="${src}.enc"
        if [ -f "$src" ]; then
            echo -n "  sops: ${file} → ${file}.enc ... "
            sops --encrypt --input-type "$ftype" --output-type "$ftype" "$src" > "$dst"
            echo -e "${GREEN}✔${NC}"
            count=$((count + 1))
        else
            echo -e "  ${YELLOW}skip: ${file} (not found)${NC}"
        fi
    done

    # Unstructured files via age
    for file in "${AGE_FILES[@]}"; do
        src="${REPO_DIR}/${file}"
        dst="${src}.enc"
        if [ -f "$src" ]; then
            echo -n "  age:  ${file} → ${file}.enc ... "
            age --encrypt --recipient "$AGE_PUBLIC_KEY" --output "$dst" "$src"
            echo -e "${GREEN}✔${NC}"
            count=$((count + 1))
        else
            echo -e "  ${YELLOW}skip: ${file} (not found)${NC}"
        fi
    done

    echo
    echo -e "${GREEN}${BOLD}Encrypted ${count} files.${NC}"
    echo -e "You can now ${YELLOW}git add${NC} the .enc files."
}

# ===========================================
# Decrypt
# ===========================================
do_decrypt() {
    check_tools
    check_age_key

    echo -e "${BOLD}Decrypting secrets...${NC}"
    echo
    local count=0

    # Structured files via sops
    for entry in "${SOPS_FILES[@]}"; do
        file="${entry%%:*}"
        ftype="${entry##*:}"
        dst="${REPO_DIR}/${file}"
        src="${dst}.enc"
        if [ -f "$src" ]; then
            # Don't overwrite if plaintext already exists and is newer
            if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
                echo -e "  ${YELLOW}skip: ${file} (plaintext is newer than encrypted)${NC}"
                continue
            fi
            echo -n "  sops: ${file}.enc → ${file} ... "
            sops --decrypt --input-type "$ftype" --output-type "$ftype" "$src" > "$dst"
            echo -e "${GREEN}✔${NC}"
            count=$((count + 1))
        else
            echo -e "  ${YELLOW}skip: ${file} (not found)${NC}"
        fi
    done

    # Unstructured files via age
    for file in "${AGE_FILES[@]}"; do
        dst="${REPO_DIR}/${file}"
        src="${dst}.enc"
        if [ -f "$src" ]; then
            if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
                echo -e "  ${YELLOW}skip: ${file} (plaintext is newer than encrypted)${NC}"
                continue
            fi
            echo -n "  age:  ${file}.enc → ${file} ... "
            age --decrypt --identity "$AGE_KEY_FILE" --output "$dst" "$src"
            echo -e "${GREEN}✔${NC}"
            count=$((count + 1))
        else
            echo -e "  ${YELLOW}skip: ${file}.enc (not found)${NC}"
        fi
    done

    echo
    echo -e "${GREEN}${BOLD}Decrypted ${count} files.${NC}"
}

# ===========================================
# Status
# ===========================================
do_status() {
    echo -e "${BOLD}Secrets status:${NC}"
    echo
    printf "  %-50s  %-12s  %-12s  %s\n" "File" "Plaintext" "Encrypted" "Method"
    printf "  %-50s  %-12s  %-12s  %s\n" "----" "---------" "---------" "------"

    for entry in "${SOPS_FILES[@]}"; do
        file="${entry%%:*}"
        plain="${REPO_DIR}/${file}"
        enc="${plain}.enc"
        p_status=$( [ -f "$plain" ] && echo -e "${GREEN}exists${NC}" || echo -e "${RED}missing${NC}" )
        e_status=$( [ -f "$enc" ]   && echo -e "${GREEN}exists${NC}" || echo -e "${RED}missing${NC}" )
        printf "  %-50s  %-21s  %-21s  %s\n" "$file" "$p_status" "$e_status" "sops"
    done

    for file in "${AGE_FILES[@]}"; do
        plain="${REPO_DIR}/${file}"
        enc="${plain}.enc"
        p_status=$( [ -f "$plain" ] && echo -e "${GREEN}exists${NC}" || echo -e "${RED}missing${NC}" )
        e_status=$( [ -f "$enc" ]   && echo -e "${GREEN}exists${NC}" || echo -e "${RED}missing${NC}" )
        printf "  %-50s  %-21s  %-21s  %s\n" "$file" "$p_status" "$e_status" "age"
    done
    echo
}

# ===========================================
# Main
# ===========================================
case "${1:-}" in
    encrypt)
        do_encrypt
        ;;
    decrypt)
        do_decrypt
        ;;
    status)
        do_status
        ;;
    *)
        echo "Usage: $0 {encrypt|decrypt|status}"
        echo
        echo "  encrypt  — Encrypt plaintext secrets → .enc files (for git)"
        echo "  decrypt  — Decrypt .enc files → plaintext secrets (after clone)"
        echo "  status   — Show which secret files exist"
        exit 1
        ;;
esac
