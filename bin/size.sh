#!/bin/bash
# Mole - Size command.
# Shows developer tool cache sizes.
# Read-only, no deletions.

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib/core/common.sh"
source "$SCRIPT_DIR/lib/size/main.sh"

size_main "$@"
