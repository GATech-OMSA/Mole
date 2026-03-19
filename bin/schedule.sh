#!/bin/bash
# Mole - Schedule command.
# Install/remove LaunchAgent for periodic maintenance.

set -euo pipefail

export LC_ALL=C
export LANG=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/core/common.sh"
source "$SCRIPT_DIR/../lib/manage/schedule.sh"

main "$@"
