#!/bin/bash
# Mole - Watch command.
# Runs the Go background threshold alert system.
# Monitors system metrics and sends macOS notifications when thresholds are breached.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GO_BIN="$SCRIPT_DIR/watch-go"
if [[ -x "$GO_BIN" ]]; then
    exec "$GO_BIN" "$@"
fi

echo "Bundled watch binary not found. Please reinstall Mole or run mo update to restore it." >&2
exit 1
