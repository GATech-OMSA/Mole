#!/bin/bash
# Mole - Report command.
# Generates a JSON system report combining status, check, and cleanup data.
# chmod +x bin/report.sh

set -euo pipefail
export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/report/main.sh"

report_main "$@"
