#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> script/wsl.sh is deprecated; use script/linux.sh"
exec bash "$SCRIPT_DIR/linux.sh" "$@"
