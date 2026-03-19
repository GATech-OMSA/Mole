#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-report.XXXXXX")"
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
    mkdir -p "$HOME/.config/mole"
}

# ============================================================================
# Basic invocation
# ============================================================================

@test "mo report produces valid JSON to stdout" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh"

    [ "$status" -eq 0 ]

    # Validate it is parseable JSON (python3 is available on macOS)
    echo "$output" | python3 -m json.tool >/dev/null 2>&1
}

@test "mo report --out writes JSON to file" {
    local out_file="$HOME/report.json"

    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh" --out "$out_file"

    [ "$status" -eq 0 ]
    [ -f "$out_file" ]

    # Validate the file contains parseable JSON
    python3 -m json.tool "$out_file" >/dev/null 2>&1
}

@test "mo report JSON contains required keys" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh"

    [ "$status" -eq 0 ]

    # Check all required keys exist in the JSON
    python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
required = ['timestamp', 'version', 'hostname', 'os_version',
            'architecture', 'free_space',
            'cleanup_potential_bytes', 'cleanup_potential_human']
for key in required:
    assert key in data, f'Missing key: {key}'
" <<< "$output"
}

@test "mo report exits 0" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh"

    [ "$status" -eq 0 ]
}

# ============================================================================
# Help flag
# ============================================================================

@test "mo report --help shows usage" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]]
    [[ "$output" == *"--out"* ]]
}

# ============================================================================
# Field value sanity
# ============================================================================

@test "mo report timestamp is ISO 8601 UTC" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh"

    [ "$status" -eq 0 ]

    python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
ts = data['timestamp']
# Must match YYYY-MM-DDTHH:MM:SSZ
import re
assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', ts), f'Bad timestamp: {ts}'
" <<< "$output"
}

@test "mo report version is 2.0.0" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh"

    [ "$status" -eq 0 ]

    python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert data['version'] == '2.0.0', f'Expected 2.0.0, got {data[\"version\"]}'
" <<< "$output"
}

@test "mo report cleanup_potential_bytes is numeric" {
    run env HOME="$HOME" MO_NO_OPLOG=1 \
        bash --noprofile --norc "$PROJECT_ROOT/bin/report.sh"

    [ "$status" -eq 0 ]

    python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
assert isinstance(data['cleanup_potential_bytes'], int), \
    f'Expected int, got {type(data[\"cleanup_potential_bytes\"])}'
" <<< "$output"
}
