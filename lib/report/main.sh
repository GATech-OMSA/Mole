#!/bin/bash
# Mole - Report module
# Combines system info into a single JSON document.

set -euo pipefail

# Prevent multiple sourcing
if [[ -n "${MOLE_REPORT_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_REPORT_LOADED=1

# Escape a string for safe JSON embedding.
# Handles backslashes, double quotes, newlines, tabs, and carriage returns.
_json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    str="${str//$'\r'/\\r}"
    printf '%s' "$str"
}

# Collect the macOS marketing version (e.g. "15.3").
_get_os_version() {
    local ver=""
    if command -v sw_vers >/dev/null 2>&1; then
        ver=$(sw_vers -productVersion 2>/dev/null || true)
    fi
    if [[ -z "$ver" ]]; then
        ver="unknown"
    fi
    printf '%s' "$ver"
}

# Collect the hardware architecture (arm64 / x86_64).
_get_architecture() {
    uname -m 2>/dev/null || printf 'unknown'
}

# Collect free disk space as a human-readable string (e.g. "150GB").
_get_report_free_space() {
    if type get_free_space >/dev/null 2>&1; then
        get_free_space
    else
        local target="/"
        if [[ -d "/System/Volumes/Data" ]]; then
            target="/System/Volumes/Data"
        fi
        df -h "$target" | awk 'NR==2 {print $4}'
    fi
}

# Try to determine total reclaimable bytes from `mo clean --dry-run`.
# Returns the byte count on stdout, or 0 if unavailable.
_get_cleanup_potential() {
    local potential_bytes=0
    local potential_human="0B"

    # Look for a 'mo' or 'mole' binary relative to SCRIPT_DIR or on PATH.
    local mo_bin=""
    if [[ -n "${SCRIPT_DIR:-}" && -x "$SCRIPT_DIR/../mole" ]]; then
        mo_bin="$SCRIPT_DIR/../mole"
    elif [[ -n "${SCRIPT_DIR:-}" && -x "$SCRIPT_DIR/../mo" ]]; then
        mo_bin="$SCRIPT_DIR/../mo"
    elif command -v mo >/dev/null 2>&1; then
        mo_bin="mo"
    elif command -v mole >/dev/null 2>&1; then
        mo_bin="mole"
    fi

    if [[ -n "$mo_bin" ]]; then
        local dry_output=""
        dry_output=$("$mo_bin" clean --dry-run 2>/dev/null || true)

        # Try to extract "Potential space: X.XXGB" from the summary
        local match=""
        match=$(printf '%s\n' "$dry_output" | grep -o '[0-9][0-9]*\.[0-9]*GB' | tail -1 || true)
        if [[ -n "$match" ]]; then
            potential_human="$match"
            # Convert to approximate bytes (base-10 GB)
            local whole="${match%%.*}"
            local frac="${match#*.}"
            frac="${frac%GB}"
            # Pad or truncate fractional part to 2 digits
            while [[ ${#frac} -lt 2 ]]; do frac="${frac}0"; done
            frac="${frac:0:2}"
            potential_bytes=$(( (whole * 100 + ${frac#0}) * 10000000 ))
        fi
    fi

    printf '%s %s' "$potential_bytes" "$potential_human"
}

# Print usage information.
_report_usage() {
    printf '%s\n' "Usage: mo report [OPTIONS]"
    printf '\n'
    printf '%s\n' "Generate a JSON system report combining status, check, and cleanup data."
    printf '\n'
    printf '%s\n' "Options:"
    printf '%s\n' "  --out <file>    Write JSON to <file> instead of stdout"
    printf '%s\n' "  --help, -h      Show this help message"
}

# Main entry point.
report_main() {
    local out_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                _report_usage
                return 0
                ;;
            --out)
                if [[ $# -lt 2 ]]; then
                    printf 'Error: --out requires a file path argument\n' >&2
                    return 1
                fi
                out_file="$2"
                shift 2
                ;;
            *)
                printf 'Unknown option: %s\n' "$1" >&2
                _report_usage >&2
                return 1
                ;;
        esac
    done

    # Gather data
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    local version="2.0.0"

    local hostname_val
    hostname_val=$(hostname -s 2>/dev/null || hostname 2>/dev/null || printf 'unknown')

    local os_version
    os_version=$(_get_os_version)

    local architecture
    architecture=$(_get_architecture)

    local free_space
    free_space=$(_get_report_free_space)

    local cleanup_potential
    cleanup_potential=$(_get_cleanup_potential)

    local cleanup_bytes="${cleanup_potential%% *}"
    local cleanup_human="${cleanup_potential#* }"

    # Build JSON manually (no jq dependency, Bash 3.2 compatible)
    local json=""
    json=$(printf '{\n')
    json+=$(printf '  "timestamp": "%s",\n' "$(_json_escape "$timestamp")")
    json+=$(printf '  "version": "%s",\n' "$(_json_escape "$version")")
    json+=$(printf '  "hostname": "%s",\n' "$(_json_escape "$hostname_val")")
    json+=$(printf '  "os_version": "%s",\n' "$(_json_escape "$os_version")")
    json+=$(printf '  "architecture": "%s",\n' "$(_json_escape "$architecture")")
    json+=$(printf '  "free_space": "%s",\n' "$(_json_escape "$free_space")")
    json+=$(printf '  "cleanup_potential_bytes": %s,\n' "$cleanup_bytes")
    json+=$(printf '  "cleanup_potential_human": "%s"\n' "$(_json_escape "$cleanup_human")")
    json+=$(printf '}\n')

    if [[ -n "$out_file" ]]; then
        printf '%s' "$json" > "$out_file"
    else
        printf '%s' "$json"
    fi
}
