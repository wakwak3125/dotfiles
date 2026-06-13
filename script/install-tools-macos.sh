#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> script/install-tools-macos.sh is deprecated; use script/macos.sh"
exec bash "$SCRIPT_DIR/macos.sh" "$@"
