#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-schedule-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
    mkdir -p "$HOME/Library/LaunchAgents"
    mkdir -p "$HOME/Library/Logs/mole"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    rm -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist"

    export MOCK_BIN_DIR="$BATS_TMPDIR/mole-schedule-mocks-$$"
    mkdir -p "$MOCK_BIN_DIR"

    # Create a mock mole binary
    cat > "$MOCK_BIN_DIR/mole" <<'SCRIPT'
#!/usr/bin/env bash
echo "mock mole $*"
SCRIPT
    chmod +x "$MOCK_BIN_DIR/mole"

    # Create a mock launchctl that records calls
    cat > "$MOCK_BIN_DIR/launchctl" <<'SCRIPT'
#!/usr/bin/env bash
echo "launchctl $*" >> "${LAUNCHCTL_LOG:-/dev/null}"
if [[ "$1" == "list" ]]; then
    if [[ "${LAUNCHCTL_LIST_OUTPUT:-}" == "loaded" ]]; then
        echo "- 0 fun.tw93.mole.maintenance"
    fi
fi
exit 0
SCRIPT
    chmod +x "$MOCK_BIN_DIR/launchctl"

    export PATH="$MOCK_BIN_DIR:$PATH"
    export LAUNCHCTL_LOG="$BATS_TMPDIR/launchctl-log-$$"
    rm -f "$LAUNCHCTL_LOG"
}

teardown() {
    rm -rf "$MOCK_BIN_DIR"
    rm -f "$LAUNCHCTL_LOG"
}

@test "schedule --help shows usage info" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main --help
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mo schedule"* ]]
    [[ "$output" == *"install"* ]]
    [[ "$output" == *"remove"* ]]
    [[ "$output" == *"status"* ]]
}

@test "schedule with no args shows help" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mo schedule"* ]]
}

@test "schedule install --dry-run shows plist without installing" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install --dry-run
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" == *"<?xml"* ]]
    [[ "$output" == *"fun.tw93.mole.maintenance"* ]]
    [[ "$output" == *"StartInterval"* ]]
    [[ "$output" == *"604800"* ]]
    # Plist file should NOT exist
    [ ! -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]
}

@test "schedule install creates plist in LaunchAgents" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"LaunchAgent installed"* ]]
    [ -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]
}

@test "schedule install plist contains correct program path and interval" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    [ "$status" -eq 0 ]
    [ -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]

    plist_content=$(cat "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist")
    [[ "$plist_content" == *"<string>$MOCK_BIN_DIR/mole</string>"* ]]
    [[ "$plist_content" == *"<string>clean</string>"* ]]
    [[ "$plist_content" == *"<string>--dry-run</string>"* ]]
    [[ "$plist_content" == *"<integer>604800</integer>"* ]]
    [[ "$plist_content" == *"fun.tw93.mole.maintenance"* ]]
    [[ "$plist_content" == *"Library/Logs/mole/schedule.log"* ]]
    [[ "$plist_content" == *"Library/Logs/mole/schedule-error.log"* ]]
}

@test "schedule install with custom interval uses provided value" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install --interval 3600
EOF

    [ "$status" -eq 0 ]
    [ -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]

    plist_content=$(cat "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist")
    [[ "$plist_content" == *"<integer>3600</integer>"* ]]
    [[ "$output" == *"1 hour"* ]]
}

@test "schedule install calls launchctl bootstrap" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    [ "$status" -eq 0 ]
    [ -f "$LAUNCHCTL_LOG" ]
    grep -q "bootstrap" "$LAUNCHCTL_LOG"
}

@test "schedule remove removes the plist" {
    # Install first
    env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    [ -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]

    # Now remove
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main remove
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"LaunchAgent removed"* ]]
    [ ! -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]
}

@test "schedule remove calls launchctl bootout" {
    # Install first
    env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    rm -f "$LAUNCHCTL_LOG"

    # Remove
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main remove
EOF

    [ "$status" -eq 0 ]
    [ -f "$LAUNCHCTL_LOG" ]
    grep -q "bootout" "$LAUNCHCTL_LOG"
}

@test "schedule remove when not installed shows warning" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main remove
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"not installed"* ]]
}

@test "schedule status shows installed state" {
    # Install first
    env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LIST_OUTPUT="loaded" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main status
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"LaunchAgent installed"* ]]
    [[ "$output" == *"1 week"* ]]
    [[ "$output" == *"loaded and active"* ]]
}

@test "schedule status shows not installed when plist missing" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main status
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"not installed"* ]]
}

@test "schedule status shows not loaded when agent exists but not active" {
    # Install first
    env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    # Status without LAUNCHCTL_LIST_OUTPUT=loaded means launchctl list returns nothing
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main status
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"LaunchAgent installed"* ]]
    [[ "$output" == *"not currently loaded"* ]]
}

@test "schedule install --dry-run with custom interval shows correct value" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install --dry-run --interval 86400
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY RUN"* ]]
    [[ "$output" == *"86400"* ]]
    [[ "$output" == *"1 day"* ]]
    [ ! -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]
}

@test "schedule install with invalid interval fails" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install --interval abc
EOF

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid interval"* ]]
}

@test "schedule install with zero interval fails" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install --interval 0
EOF

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid interval"* ]]
}

@test "schedule unknown command shows error" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main bogus
EOF

    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]]
}

@test "schedule install replaces existing plist" {
    # Install with default interval
    env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    [ -f "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist" ]
    plist_v1=$(cat "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist")
    [[ "$plist_v1" == *"604800"* ]]

    rm -f "$LAUNCHCTL_LOG"

    # Re-install with different interval
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install --interval 3600
EOF

    [ "$status" -eq 0 ]
    plist_v2=$(cat "$HOME/Library/LaunchAgents/fun.tw93.mole.maintenance.plist")
    [[ "$plist_v2" == *"3600"* ]]
    # Should bootout old agent before bootstrap
    [ -f "$LAUNCHCTL_LOG" ]
    grep -q "bootout" "$LAUNCHCTL_LOG"
    grep -q "bootstrap" "$LAUNCHCTL_LOG"
}

@test "format_interval_human produces correct labels" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
echo "$(format_interval_human 30)"
echo "$(format_interval_human 60)"
echo "$(format_interval_human 120)"
echo "$(format_interval_human 3600)"
echo "$(format_interval_human 7200)"
echo "$(format_interval_human 86400)"
echo "$(format_interval_human 172800)"
echo "$(format_interval_human 604800)"
echo "$(format_interval_human 1209600)"
EOF

    [ "$status" -eq 0 ]
    lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done <<< "$output"
    [ "${lines[0]}" = "30 seconds" ]
    [ "${lines[1]}" = "1 minute" ]
    [ "${lines[2]}" = "2 minutes" ]
    [ "${lines[3]}" = "1 hour" ]
    [ "${lines[4]}" = "2 hours" ]
    [ "${lines[5]}" = "1 day" ]
    [ "${lines[6]}" = "2 days" ]
    [ "${lines[7]}" = "1 week" ]
    [ "${lines[8]}" = "2 weeks" ]
}

@test "generate_plist produces valid XML structure" {
    run bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
generate_plist "/usr/local/bin/mole" 604800
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *'<?xml version="1.0"'* ]]
    [[ "$output" == *'<!DOCTYPE plist'* ]]
    [[ "$output" == *'<plist version="1.0">'* ]]
    [[ "$output" == *'</plist>'* ]]
    [[ "$output" == *'<key>Label</key>'* ]]
    [[ "$output" == *'<key>ProgramArguments</key>'* ]]
    [[ "$output" == *'<key>StartInterval</key>'* ]]
    [[ "$output" == *'<key>StandardOutPath</key>'* ]]
    [[ "$output" == *'<key>StandardErrorPath</key>'* ]]
}

@test "schedule install exits 0" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        LAUNCHCTL_LOG="$LAUNCHCTL_LOG" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main install
EOF

    [ "$status" -eq 0 ]
}

@test "schedule remove exits 0" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main remove
EOF

    [ "$status" -eq 0 ]
}

@test "schedule status exits 0" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$MOCK_BIN_DIR:$PATH" \
        bash --noprofile --norc <<'EOF'
set -euo pipefail
export MO_NO_OPLOG=1
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/schedule.sh"
main status
EOF

    [ "$status" -eq 0 ]
}
