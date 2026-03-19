#!/bin/bash
# Mole - Log viewer command.
# Human-friendly viewer for operations.log.

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/log/viewer.sh"

main "$@"
