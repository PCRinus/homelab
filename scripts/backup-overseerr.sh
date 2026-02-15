#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "backup-overseerr.sh is deprecated; running backup-seerr.sh instead..."
exec "${SCRIPT_DIR}/backup-seerr.sh" "$@"
