#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-doctor.XXXXXX")"
    export HOME

    mkdir -p "$HOME"
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
}

setup() {
    mkdir -p "$HOME"
}

# ============================================================================
# Basic invocation
# ============================================================================

@test "doctor exits 0 with checklist output" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

# Mock external commands to avoid side effects
xcode-select() { echo "$HOME"; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "Test User" ;;
        user.email) echo "test@example.com" ;;
    esac
}
export -f git
brew() { echo "Your system is ready to brew."; return 0; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { echo "Python 3.11.0"; }
export -f python3
node() { echo "v20.0.0"; }
export -f node

main
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Xcode"* ]]
}

# ============================================================================
# Xcode CLT detection
# ============================================================================

@test "doctor detects missing Xcode CLT" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

# Mock xcode-select to simulate missing CLT
xcode-select() { return 2; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "Test User" ;;
        user.email) echo "test@example.com" ;;
    esac
}
export -f git
brew() { return 1; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { return 1; }
export -f python3
node() { return 1; }
export -f node

main
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Xcode CLT"* ]]
    [[ "$output" == *"xcode-select --install"* ]]
}

@test "doctor detects Xcode CLT with missing path" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

# xcode-select returns a path, but the path does not exist
xcode-select() { echo "/nonexistent/Developer"; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "Test User" ;;
        user.email) echo "test@example.com" ;;
    esac
}
export -f git
brew() { return 1; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { return 1; }
export -f python3
node() { return 1; }
export -f node

main
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Xcode CLT"* ]]
    [[ "$output" == *"xcode-select --install"* ]]
}

# ============================================================================
# Broken symlinks in PATH
# ============================================================================

@test "doctor detects broken symlinks in PATH" {
    # Create a directory with a broken symlink
    local test_bin="$HOME/test-bin"
    mkdir -p "$test_bin"
    ln -s "/nonexistent/target/binary" "$test_bin/broken_tool"

    run env HOME="$HOME" PATH="$test_bin:$PATH" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

xcode-select() { echo "$HOME"; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "Test User" ;;
        user.email) echo "test@example.com" ;;
    esac
}
export -f git
brew() { return 1; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { return 1; }
export -f python3
node() { return 1; }
export -f node

main
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"broken_tool"* ]]
}

# ============================================================================
# Git identity
# ============================================================================

@test "doctor detects git identity not configured" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

xcode-select() { echo "$HOME"; }
export -f xcode-select
# Git returns empty for user.name and user.email
git() {
    case "$3" in
        user.name) echo "" ;;
        user.email) echo "" ;;
        *) command git "$@" 2>/dev/null || true ;;
    esac
}
export -f git
brew() { return 1; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { return 1; }
export -f python3
node() { return 1; }
export -f node

main
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
    [[ "$output" == *"git config"* ]]
}

# ============================================================================
# Fix hints
# ============================================================================

@test "doctor shows fix hints for each failed check" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

# Fail all checks to get all hints
xcode-select() { return 2; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "" ;;
        user.email) echo "" ;;
    esac
}
export -f git
brew() { echo "Warning: some problem"; return 1; }
export -f brew
diskutil() { echo "   SMART Status:             Failing"; }
export -f diskutil
python3() { return 1; }
export -f python3
node() { return 1; }
export -f node

main
EOF

    [ "$status" -eq 0 ]
    # Should contain fix hints (shown in gray after each failed check)
    [[ "$output" == *"xcode-select --install"* ]]
    [[ "$output" == *"git config"* ]]
}

# ============================================================================
# JSON output
# ============================================================================

@test "--json produces valid JSON" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

xcode-select() { echo "$HOME"; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "Test User" ;;
        user.email) echo "test@example.com" ;;
    esac
}
export -f git
brew() { echo "Your system is ready to brew."; return 0; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { echo "Python 3.11.0"; }
export -f python3
node() { echo "v20.0.0"; }
export -f node

main --json
EOF

    [ "$status" -eq 0 ]
    # Validate basic JSON structure
    [[ "$output" == "{"* ]]
    [[ "$output" == *"}"* ]]
    [[ "$output" == *'"checks"'* ]]
    [[ "$output" == *'"status"'* ]]
}

@test "--json includes pass and fail statuses" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"

# Pass xcode, fail git
xcode-select() { echo "$HOME"; }
export -f xcode-select
git() {
    case "$3" in
        user.name) echo "" ;;
        user.email) echo "" ;;
    esac
}
export -f git
brew() { return 1; }
export -f brew
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
python3() { return 1; }
export -f python3
node() { return 1; }
export -f node

main --json
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *'"pass"'* ]]
    [[ "$output" == *'"fail"'* ]]
}

# ============================================================================
# Help flag
# ============================================================================

@test "--help shows usage information" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
main --help
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"doctor"* ]]
}

# ============================================================================
# Individual check functions
# ============================================================================

@test "check_xcode_clt passes when CLT installed" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
xcode-select() { echo "$HOME"; }
export -f xcode-select
check_xcode_clt
print_checklist
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Xcode CLT"* ]]
}

@test "check_git_identity passes when configured" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
git() {
    case "$3" in
        user.name) echo "Test User" ;;
        user.email) echo "test@example.com" ;;
    esac
}
export -f git
check_git_identity
print_checklist
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Git"* ]]
}

@test "check_python_version passes when python3 exists" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
python3() { echo "Python 3.11.0"; }
export -f python3
check_python_version
print_checklist
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Python"* ]]
}

@test "check_node_version passes when node exists" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
node() { echo "v20.0.0"; }
export -f node
check_node_version
print_checklist
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Node"* ]]
}

@test "check_disk_smart passes with Verified status" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
diskutil() { echo "   SMART Status:             Verified"; }
export -f diskutil
check_disk_smart
print_checklist
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk SMART"* ]]
}

@test "check_disk_smart warns on failing status" {
    run env HOME="$HOME" PROJECT_ROOT="$PROJECT_ROOT" bash --noprofile --norc <<'EOF'
set -euo pipefail
export LC_ALL=C
source "$PROJECT_ROOT/lib/core/common.sh"
source "$PROJECT_ROOT/lib/doctor/checks.sh"
diskutil() { echo "   SMART Status:             Failing"; }
export -f diskutil
check_disk_smart
print_checklist
EOF

    [ "$status" -eq 0 ]
    [[ "$output" == *"Disk SMART"* ]]
    [[ "$output" == *"Failing"* ]]
}
