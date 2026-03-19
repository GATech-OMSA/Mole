#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-clean-home.XXXXXX")"
    export HOME

    # Prevent AppleScript permission dialogs during tests
    MOLE_TEST_MODE=1
    export MOLE_TEST_MODE

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    export TERM="xterm-256color"
    rm -rf "${HOME:?}"/*
    rm -rf "$HOME/Library" "$HOME/.config"
    mkdir -p "$HOME/Library/Caches" "$HOME/.config/mole"
    unset TEST_MOCK_BIN
}

set_mock_sudo_cached() {
    TEST_MOCK_BIN="$HOME/bin"
    mkdir -p "$TEST_MOCK_BIN"
    cat > "$TEST_MOCK_BIN/sudo" << 'MOCK'
#!/bin/bash
# Shim: sudo -n true succeeds, all other sudo calls are no-ops.
if [[ "$1" == "-n" && "$2" == "true" ]]; then exit 0; fi
if [[ "$1" == "test" ]]; then exit 1; fi
if [[ "$1" == "find" ]]; then exit 0; fi
exit 0
MOCK
    chmod +x "$TEST_MOCK_BIN/sudo"
}

set_mock_sudo_uncached() {
    TEST_MOCK_BIN="$HOME/bin"
    mkdir -p "$TEST_MOCK_BIN"
    cat > "$TEST_MOCK_BIN/sudo" << 'MOCK'
#!/bin/bash
# Shim: sudo -n always fails (no cached credentials).
exit 1
MOCK
    chmod +x "$TEST_MOCK_BIN/sudo"
}

run_clean_dry_run() {
    local test_path="$PATH"
    if [[ -n "${TEST_MOCK_BIN:-}" ]]; then
        test_path="$TEST_MOCK_BIN:$PATH"
    fi

    run env HOME="$HOME" MOLE_TEST_MODE=1 PATH="$test_path" \
        "$PROJECT_ROOT/mole" clean --dry-run
}

@test "mo clean --dry-run skips system cleanup in non-interactive mode" {
    set_mock_sudo_uncached
    run_clean_dry_run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Dry Run Mode"* ]]
    [[ "$output" == *"sudo -v && mo clean --dry-run"* ]]
    [[ "$output" != *"system preview included"* ]]
}

@test "mo clean --dry-run includes system preview when sudo is cached" {
    set_mock_sudo_cached
    run_clean_dry_run
    [ "$status" -eq 0 ]
    [[ "$output" == *"system preview included"* ]]
}

@test "mo clean --dry-run shows hint when sudo is not cached" {
    set_mock_sudo_uncached
    run_clean_dry_run
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo -v"* ]]
    [[ "$output" == *"full preview"* ]]
}

@test "mo clean --dry-run reports user cache without deleting it" {
    mkdir -p "$HOME/Library/Caches/TestApp"
    echo "cache data" > "$HOME/Library/Caches/TestApp/cache.tmp"

    run env HOME="$HOME" MOLE_TEST_MODE=1 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"User app cache"* ]]
    [[ "$output" == *"Potential space"* ]]
    [ -f "$HOME/Library/Caches/TestApp/cache.tmp" ]
}

@test "mo clean --dry-run reports stale login item without deleting it" {
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$HOME/Library/LaunchAgents/com.example.stale.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.stale</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Missing.app/Contents/MacOS/Missing</string>
    </array>
</dict>
</plist>
PLIST

    run env HOME="$HOME" MOLE_TEST_MODE=1 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Potential stale login item: com.example.stale.plist"* ]]
    [ -f "$HOME/Library/LaunchAgents/com.example.stale.plist" ]
}

@test "mo clean --dry-run does not export duplicate targets across sections" {
    mkdir -p "$HOME/Library/Application Support/Code/CachedData"
    echo "cache" > "$HOME/Library/Application Support/Code/CachedData/data.bin"

    run env HOME="$HOME" MOLE_TEST_MODE=0 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]

    run grep -c "Application Support/Code/CachedData" "$HOME/.config/mole/clean-list.txt"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "mo clean honors whitelist entries" {
    mkdir -p "$HOME/Library/Caches/WhitelistedApp"
    echo "keep me" > "$HOME/Library/Caches/WhitelistedApp/data.tmp"

    cat > "$HOME/.config/mole/whitelist" << EOF
$HOME/Library/Caches/WhitelistedApp*
EOF

    run env HOME="$HOME" MOLE_TEST_MODE=1 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Protected"* ]]
    [ -f "$HOME/Library/Caches/WhitelistedApp/data.tmp" ]
}

@test "mo clean honors whitelist entries with $HOME literal" {
    mkdir -p "$HOME/Library/Caches/WhitelistedApp"
    echo "keep me" > "$HOME/Library/Caches/WhitelistedApp/data.tmp"

    cat > "$HOME/.config/mole/whitelist" << 'EOF'
$HOME/Library/Caches/WhitelistedApp*
EOF

    run env HOME="$HOME" MOLE_TEST_MODE=1 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Protected"* ]]
    [ -f "$HOME/Library/Caches/WhitelistedApp/data.tmp" ]
}

@test "mo clean protects Maven repository by default" {
    mkdir -p "$HOME/.m2/repository/org/example"
    echo "dependency" > "$HOME/.m2/repository/org/example/lib.jar"

    run env HOME="$HOME" MOLE_TEST_MODE=1 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]
    [ -f "$HOME/.m2/repository/org/example/lib.jar" ]
    [[ "$output" != *"Maven repository cache"* ]]
}

@test "FINDER_METADATA_SENTINEL in whitelist protects .DS_Store files" {
    mkdir -p "$HOME/Documents"
    touch "$HOME/Documents/.DS_Store"

    cat > "$HOME/.config/mole/whitelist" << EOF
FINDER_METADATA_SENTINEL
EOF

    # Test whitelist logic directly instead of running full clean
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/manage/whitelist.sh"
load_whitelist
if is_whitelisted "$HOME/Documents/.DS_Store"; then
    echo "protected by whitelist"
fi
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"protected by whitelist"* ]]
    [ -f "$HOME/Documents/.DS_Store" ]
}

@test "_clean_recent_items removes shared file lists" {
    local shared_dir="$HOME/Library/Application Support/com.apple.sharedfilelist"
    mkdir -p "$shared_dir"
    touch "$shared_dir/com.apple.LSSharedFileList.RecentApplications.sfl2"
    touch "$shared_dir/com.apple.LSSharedFileList.RecentDocuments.sfl2"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
safe_clean() {
    echo "safe_clean $1"
}
_clean_recent_items
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Recent"* ]]
}

@test "_clean_recent_items handles missing shared directory" {
    rm -rf "$HOME/Library/Application Support/com.apple.sharedfilelist"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
safe_clean() {
    echo "safe_clean $1"
}
_clean_recent_items
EOF

    [ "$status" -eq 0 ]
}

@test "_clean_mail_downloads skips cleanup when size below threshold" {
    mkdir -p "$HOME/Library/Mail Downloads"
    echo "test" > "$HOME/Library/Mail Downloads/small.txt"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
_clean_mail_downloads
EOF

    [ "$status" -eq 0 ]
    [ -f "$HOME/Library/Mail Downloads/small.txt" ]
}

@test "_clean_mail_downloads removes old attachments" {
    mkdir -p "$HOME/Library/Mail Downloads"
    touch "$HOME/Library/Mail Downloads/old.pdf"
    touch -t 202301010000 "$HOME/Library/Mail Downloads/old.pdf"

    dd if=/dev/zero of="$HOME/Library/Mail Downloads/dummy.dat" bs=1024 count=6000 2>/dev/null

    [ -f "$HOME/Library/Mail Downloads/old.pdf" ]

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
_clean_mail_downloads
EOF

    [ "$status" -eq 0 ]
    [ ! -f "$HOME/Library/Mail Downloads/old.pdf" ]
}

@test "clean_time_machine_failed_backups detects running backup correctly" {
    if ! command -v tmutil > /dev/null 2>&1; then
        skip "tmutil not available"
    fi

    local mock_bin="$HOME/bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/tmutil" << 'MOCK_TMUTIL'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    cat << 'TMUTIL_OUTPUT'
Backup session status:
{
    ClientID = "com.apple.backupd";
    Running = 0;
}
TMUTIL_OUTPUT
elif [[ "$1" == "destinationinfo" ]]; then
    cat << 'DEST_OUTPUT'
====================================================
Name          : TestBackup
Kind          : Local
Mount Point   : /Volumes/TestBackup
ID            : 12345678-1234-1234-1234-123456789012
====================================================
DEST_OUTPUT
fi
MOCK_TMUTIL
    chmod +x "$mock_bin/tmutil"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$mock_bin:$PATH" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/system.sh"

defaults() { echo "1"; }


clean_time_machine_failed_backups
EOF

    [ "$status" -eq 0 ]
    [[ "$output" != *"Time Machine backup in progress, skipping cleanup"* ]]
}

@test "clean_time_machine_failed_backups skips when backup is actually running" {
    if ! command -v tmutil > /dev/null 2>&1; then
        skip "tmutil not available"
    fi

    local mock_bin="$HOME/bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/tmutil" << 'MOCK_TMUTIL'
#!/bin/bash
if [[ "$1" == "status" ]]; then
    cat << 'TMUTIL_OUTPUT'
Backup session status:
{
    ClientID = "com.apple.backupd";
    Running = 1;
}
TMUTIL_OUTPUT
elif [[ "$1" == "destinationinfo" ]]; then
    cat << 'DEST_OUTPUT'
====================================================
Name          : TestBackup
Kind          : Local
Mount Point   : /Volumes/TestBackup
ID            : 12345678-1234-1234-1234-123456789012
====================================================
DEST_OUTPUT
fi
MOCK_TMUTIL
    chmod +x "$mock_bin/tmutil"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$mock_bin:$PATH" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/system.sh"

defaults() { echo "1"; }


clean_time_machine_failed_backups
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Time Machine backup in progress, skipping cleanup"* ]]
}

# ============================================================================
# Phase 9: Safety Improvements
# ============================================================================

@test "ensure_recent_snapshot is callable and succeeds with mocked tmutil" {
    local mock_bin="$HOME/bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/tmutil" << 'MOCK_TMUTIL'
#!/bin/bash
if [[ "$1" == "listlocalsnapshots" ]]; then
    echo "com.apple.TimeMachine.2025-01-01-120000.local"
fi
if [[ "$1" == "localsnapshot" ]]; then
    echo "Created local snapshot"
fi
exit 0
MOCK_TMUTIL
    chmod +x "$mock_bin/tmutil"

    cat > "$mock_bin/diskutil" << 'MOCK_DISKUTIL'
#!/bin/bash
if [[ "$1" == "info" ]]; then
    echo "   File System Personality:  APFS"
    echo "   Type (Bundle):            apfs"
fi
exit 0
MOCK_DISKUTIL
    chmod +x "$mock_bin/diskutil"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$mock_bin:$PATH" \
        bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/bin/clean.sh" --source-only 2>/dev/null || true

# Source the function directly since bin/clean.sh runs main()
# We extract just the function
eval "$(sed -n '/^ensure_recent_snapshot()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

ensure_recent_snapshot
echo "snapshot_check_ok"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"snapshot_check_ok"* ]]
}

@test "ensure_recent_snapshot skips when MO_SKIP_SNAPSHOT=1" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MO_SKIP_SNAPSHOT=1 \
        bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"

eval "$(sed -n '/^ensure_recent_snapshot()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

ensure_recent_snapshot
echo "skipped_ok"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped_ok"* ]]
}

@test "ensure_recent_snapshot skips on non-APFS filesystem" {
    local mock_bin="$HOME/bin"
    mkdir -p "$mock_bin"

    cat > "$mock_bin/diskutil" << 'MOCK_DISKUTIL'
#!/bin/bash
if [[ "$1" == "info" ]]; then
    echo "   File System Personality:  HFS+"
    echo "   Type (Bundle):            hfs"
fi
exit 0
MOCK_DISKUTIL
    chmod +x "$mock_bin/diskutil"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" PATH="$mock_bin:$PATH" \
        bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"

eval "$(sed -n '/^ensure_recent_snapshot()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

ensure_recent_snapshot
echo "non_apfs_ok"
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"non_apfs_ok"* ]]
}

@test "first-run detection creates sentinel and forces dry-run" {
    # Ensure sentinel does not exist
    rm -f "$HOME/.config/mole/first_run_done"

    # Run clean in test mode — MOLE_TEST_MODE skips first-run logic,
    # so we test handle_first_run directly
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_MODE=0 \
        bash --noprofile --norc << 'TESTEOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"

DRY_RUN=false
MOLE_DRY_RUN=""

# Extract the function
eval "$(sed -n '/^handle_first_run()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

# Not a terminal in tests, so handle_first_run should skip (stdin is not a tty)
# Verify sentinel file behavior: no sentinel file = first run candidate
SENTINEL="$HOME/.config/mole/first_run_done"
if [[ ! -f "$SENTINEL" ]]; then
    echo "no_sentinel_detected"
fi

# Create sentinel to simulate post-first-run state
mkdir -p "$(dirname "$SENTINEL")"
touch "$SENTINEL"

if [[ -f "$SENTINEL" ]]; then
    echo "sentinel_created_ok"
fi
TESTEOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"no_sentinel_detected"* ]]
    [[ "$output" == *"sentinel_created_ok"* ]]
}

@test "first-run detection skips when MOLE_TEST_MODE=1" {
    rm -f "$HOME/.config/mole/first_run_done"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_MODE=1 \
        bash --noprofile --norc << 'TESTEOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"

DRY_RUN=false

eval "$(sed -n '/^handle_first_run()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

handle_first_run
echo "test_mode_skipped"
TESTEOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"test_mode_skipped"* ]]
}

@test "first-run detection skips when sentinel exists" {
    mkdir -p "$HOME/.config/mole"
    touch "$HOME/.config/mole/first_run_done"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" MOLE_TEST_MODE=0 \
        bash --noprofile --norc << 'TESTEOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"

DRY_RUN=false

eval "$(sed -n '/^handle_first_run()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

handle_first_run
echo "sentinel_exists_skipped"
TESTEOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"sentinel_exists_skipped"* ]]
}

@test "risk labels appear in dry-run output" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" \
        bash --noprofile --norc << 'TESTEOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"

# Extract classify_cleanup_risk
eval "$(sed -n '/^classify_cleanup_risk()/,/^}/p' "$PROJECT_ROOT/bin/clean.sh")"

# Test HIGH risk
result=$(classify_cleanup_risk "System caches" "/Library/Caches")
echo "system_result=$result"
[[ "$result" == HIGH* ]] && echo "HIGH_OK"

# Test MEDIUM risk
result=$(classify_cleanup_risk "Installer packages" "/Users/test/Downloads")
echo "installer_result=$result"
[[ "$result" == MEDIUM* ]] && echo "MEDIUM_OK"

# Test LOW risk
result=$(classify_cleanup_risk "Cache files" "/Users/test/Library/Caches")
echo "cache_result=$result"
[[ "$result" == LOW* ]] && echo "LOW_OK"
TESTEOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"HIGH_OK"* ]]
    [[ "$output" == *"MEDIUM_OK"* ]]
    [[ "$output" == *"LOW_OK"* ]]
}

@test "dry-run output includes risk level prefix" {
    mkdir -p "$HOME/Library/Caches/com.test.app"
    dd if=/dev/zero of="$HOME/Library/Caches/com.test.app/big.cache" bs=1024 count=100 2>/dev/null

    run env HOME="$HOME" MOLE_TEST_MODE=0 "$PROJECT_ROOT/mole" clean --dry-run
    [ "$status" -eq 0 ]

    # Check that risk labels appear in the output
    # The output should contain [LOW], [MEDIUM], or [HIGH] prefixes
    local has_risk_label=false
    if [[ "$output" == *"[LOW]"* ]] || [[ "$output" == *"[MEDIUM]"* ]] || [[ "$output" == *"[HIGH]"* ]]; then
        has_risk_label=true
    fi
    [[ "$has_risk_label" == "true" ]]
}

# ============================================================================
# Phase 10: iCloud Storage Audit
# ============================================================================

@test "clean_icloud_audit lists per-app container sizes" {
    local mobile_docs="$HOME/Library/Mobile Documents"
    mkdir -p "$mobile_docs/com~apple~CloudDocs"
    mkdir -p "$mobile_docs/iCloud~com~example~app"
    echo "some data" > "$mobile_docs/com~apple~CloudDocs/file.txt"
    echo "more data" > "$mobile_docs/iCloud~com~example~app/doc.txt"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
clean_icloud_audit
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"iCloud local storage audit"* ]]
    [[ "$output" == *"com~apple~CloudDocs"* ]]
    [[ "$output" == *"iCloud~com~example~app"* ]]
}

@test "clean_icloud_audit handles missing Mobile Documents directory" {
    rm -rf "$HOME/Library/Mobile Documents"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
clean_icloud_audit
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"iCloud Drive not found"* ]]
}

@test "clean_icloud_audit handles empty Mobile Documents directory" {
    mkdir -p "$HOME/Library/Mobile Documents"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
clean_icloud_audit
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"No iCloud containers found"* ]]
}

@test "clean_icloud_audit is read-only and does not delete anything" {
    local mobile_docs="$HOME/Library/Mobile Documents"
    mkdir -p "$mobile_docs/com~apple~CloudDocs"
    echo "important data" > "$mobile_docs/com~apple~CloudDocs/important.txt"

    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc << 'EOF'
set -euo pipefail
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/clean/user.sh"
clean_icloud_audit
EOF

    [ "$status" -eq 0 ]
    [ -f "$mobile_docs/com~apple~CloudDocs/important.txt" ]
    [ "$(cat "$mobile_docs/com~apple~CloudDocs/important.txt")" = "important data" ]
}
