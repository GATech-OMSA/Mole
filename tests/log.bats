#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-log-home.XXXXXX")"
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
    export TERM="xterm-256color"
    export MO_NO_OPLOG=1
    rm -rf "${HOME:?}"/*
    mkdir -p "$HOME/Library/Logs/mole"
}

@test "mo log displays formatted log entries" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:45] [clean] REMOVED /Users/test/.npm/_cacache (15.2MB)
[2024-03-15 10:30:46] [clean] SKIPPED /Users/test/.cargo (whitelist)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REMOVED"* ]]
    [[ "$output" == *"/Users/test/.npm/_cacache"* ]]
    [[ "$output" == *"SKIPPED"* ]]
    [[ "$output" == *"/Users/test/.cargo"* ]]
}

@test "mo log --since filters by date" {
    # Entry from far in the past
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2020-01-01 00:00:00] [clean] REMOVED /Users/test/old-file (1.0MB)
EOF
    # Append a recent entry (today)
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$now] [clean] REMOVED /Users/test/new-file (2.0MB)" >> "$HOME/Library/Logs/mole/operations.log"

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --since 7d
    [ "$status" -eq 0 ]
    [[ "$output" == *"new-file"* ]]
    [[ "$output" != *"old-file"* ]]
}

@test "mo log --grep filters by keyword" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:45] [clean] REMOVED /Users/test/.npm/_cacache (15.2MB)
[2024-03-15 10:30:46] [optimize] REBUILT /Users/test/Spotlight (index)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --grep clean
    [ "$status" -eq 0 ]
    [[ "$output" == *"REMOVED"* ]]
    [[ "$output" == *".npm"* ]]
    [[ "$output" != *"REBUILT"* ]]
    [[ "$output" != *"Spotlight"* ]]
}

@test "mo log --grep is case-insensitive" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:45] [clean] REMOVED /Users/test/.npm/_cacache (15.2MB)
[2024-03-15 10:30:46] [optimize] REBUILT /Users/test/Spotlight (index)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --grep CLEAN
    [ "$status" -eq 0 ]
    [[ "$output" == *"REMOVED"* ]]
    [[ "$output" != *"REBUILT"* ]]
}

@test "mo log --tail shows last N entries" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:01] [clean] REMOVED /Users/test/file1 (1MB)
[2024-03-15 10:30:02] [clean] REMOVED /Users/test/file2 (2MB)
[2024-03-15 10:30:03] [clean] REMOVED /Users/test/file3 (3MB)
[2024-03-15 10:30:04] [clean] REMOVED /Users/test/file4 (4MB)
[2024-03-15 10:30:05] [clean] REMOVED /Users/test/file5 (5MB)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --tail 2
    [ "$status" -eq 0 ]
    [[ "$output" == *"file4"* ]]
    [[ "$output" == *"file5"* ]]
    [[ "$output" != *"file1"* ]]
    [[ "$output" != *"file2"* ]]
    [[ "$output" != *"file3"* ]]
}

@test "mo log shows message when log is empty" {
    : > "$HOME/Library/Logs/mole/operations.log"

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No log entries found"* ]]
}

@test "mo log shows message when log is missing" {
    rm -f "$HOME/Library/Logs/mole/operations.log"

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No log entries found"* ]]
}

@test "mo log exits 0" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:45] [clean] REMOVED /Users/test/.npm/_cacache (15.2MB)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh"
    [ "$status" -eq 0 ]
}

@test "mo log --help shows usage" {
    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--since"* ]]
    [[ "$output" == *"--grep"* ]]
    [[ "$output" == *"--tail"* ]]
}

@test "mo log skips comment and blank lines" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'

# ========== clean session started at 2024-03-15 10:30:00 ==========
[2024-03-15 10:30:45] [clean] REMOVED /Users/test/.npm/_cacache (15.2MB)
# ========== clean session ended at 2024-03-15 10:31:00, 1 items, 15.2MB ==========

EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"REMOVED"* ]]
    [[ "$output" != *"=========="* ]]
}

@test "mo log --since with hours duration" {
    # Entry from far in the past
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2020-01-01 00:00:00] [clean] REMOVED /Users/test/ancient-file (1.0MB)
EOF
    # Append a recent entry (now)
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$now] [clean] REMOVED /Users/test/recent-file (2.0MB)" >> "$HOME/Library/Logs/mole/operations.log"

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --since 1h
    [ "$status" -eq 0 ]
    [[ "$output" == *"recent-file"* ]]
    [[ "$output" != *"ancient-file"* ]]
}

@test "mo log --since with minutes duration" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2020-01-01 00:00:00] [clean] REMOVED /Users/test/ancient-file (1.0MB)
EOF
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$now] [clean] REMOVED /Users/test/recent-file (2.0MB)" >> "$HOME/Library/Logs/mole/operations.log"

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --since 30m
    [ "$status" -eq 0 ]
    [[ "$output" == *"recent-file"* ]]
    [[ "$output" != *"ancient-file"* ]]
}

@test "mo log FAILED entries are shown" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:45] [clean] FAILED /Users/test/locked-file (permission denied)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FAILED"* ]]
    [[ "$output" == *"locked-file"* ]]
}

@test "mo log --tail and --grep can be combined" {
    cat > "$HOME/Library/Logs/mole/operations.log" << 'EOF'
[2024-03-15 10:30:01] [clean] REMOVED /Users/test/clean-file1 (1MB)
[2024-03-15 10:30:02] [optimize] REBUILT /Users/test/spotlight-index (index)
[2024-03-15 10:30:03] [clean] REMOVED /Users/test/clean-file2 (2MB)
[2024-03-15 10:30:04] [clean] REMOVED /Users/test/clean-file3 (3MB)
[2024-03-15 10:30:05] [optimize] REBUILT /Users/test/dns-cache (cache)
EOF

    run env HOME="$HOME" MO_NO_OPLOG=1 "$PROJECT_ROOT/bin/log.sh" --grep clean --tail 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean-file3"* ]]
    [[ "$output" != *"clean-file1"* ]]
    [[ "$output" != *"clean-file2"* ]]
    [[ "$output" != *"spotlight"* ]]
    [[ "$output" != *"dns-cache"* ]]
}
