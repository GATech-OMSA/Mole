#!/bin/bash
# Mole - Size command module
# Read-only: shows a sorted table of all developer tool cache sizes.

set -euo pipefail
export LC_ALL=C

# Prevent multiple sourcing
if [[ -n "${MOLE_SIZE_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_SIZE_LOADED=1

# ============================================================================
# Cache Registry
# ============================================================================
# Each entry: "Label|RelativePath" (relative to $HOME)
# Paths starting with '/' are treated as absolute.

_size_cache_entries() {
    local entries=""
    entries="npm|.npm
pnpm store|.pnpm-store
Yarn|.yarn
Homebrew|Library/Caches/Homebrew
Cargo|.cargo
Go build cache|Library/Caches/go-build
Go module cache|go/pkg/mod
Gradle caches|.gradle/caches
Maven repository|.m2/repository
pip|Library/Caches/pip
uv|.cache/uv
Xcode DerivedData|Library/Developer/Xcode/DerivedData
Docker|.docker
Colima|.colima
CocoaPods|Library/Caches/CocoaPods
pre-commit|.cache/pre-commit
Terraform plugins|.terraform.d/plugin-cache"
    printf '%s\n' "$entries"
}

# ============================================================================
# Core Functions
# ============================================================================

# Collect cache sizes into parallel arrays (Bash 3.2 compatible).
# Sets: _SIZE_NAMES, _SIZE_BYTES, _SIZE_PATHS, _SIZE_COUNT
_SIZE_NAMES=()
_SIZE_BYTES=()
_SIZE_PATHS=()
_SIZE_COUNT=0

_collect_cache_sizes() {
    _SIZE_NAMES=()
    _SIZE_BYTES=()
    _SIZE_PATHS=()
    _SIZE_COUNT=0

    while IFS='|' read -r label rel_path; do
        [[ -z "$label" || -z "$rel_path" ]] && continue

        local full_path
        if [[ "$rel_path" == /* ]]; then
            full_path="$rel_path"
        else
            full_path="$HOME/$rel_path"
        fi

        [[ -d "$full_path" ]] || continue

        local size_kb
        size_kb=$(get_path_size_kb "$full_path")
        [[ "$size_kb" =~ ^[0-9]+$ ]] || size_kb=0
        [[ "$size_kb" -eq 0 ]] && continue

        local size_bytes=$((size_kb * 1024))

        _SIZE_NAMES+=("$label")
        _SIZE_BYTES+=("$size_bytes")
        _SIZE_PATHS+=("$full_path")
        _SIZE_COUNT=$((_SIZE_COUNT + 1))
    done < <(_size_cache_entries)
}

# Sort parallel arrays by _SIZE_BYTES descending (selection sort, Bash 3.2 safe).
_sort_by_size_desc() {
    [[ $_SIZE_COUNT -le 1 ]] && return 0
    local i j max_idx tmp_name tmp_bytes tmp_path
    for ((i = 0; i < _SIZE_COUNT - 1; i++)); do
        max_idx=$i
        for ((j = i + 1; j < _SIZE_COUNT; j++)); do
            if [[ "${_SIZE_BYTES[$j]}" -gt "${_SIZE_BYTES[$max_idx]}" ]]; then
                max_idx=$j
            fi
        done
        if [[ $max_idx -ne $i ]]; then
            tmp_name="${_SIZE_NAMES[$i]}"
            tmp_bytes="${_SIZE_BYTES[$i]}"
            tmp_path="${_SIZE_PATHS[$i]}"
            _SIZE_NAMES[$i]="${_SIZE_NAMES[$max_idx]}"
            _SIZE_BYTES[$i]="${_SIZE_BYTES[$max_idx]}"
            _SIZE_PATHS[$i]="${_SIZE_PATHS[$max_idx]}"
            _SIZE_NAMES[$max_idx]="$tmp_name"
            _SIZE_BYTES[$max_idx]="$tmp_bytes"
            _SIZE_PATHS[$max_idx]="$tmp_path"
        fi
    done
}

# ============================================================================
# Output: Table
# ============================================================================

_print_table() {
    # Compute column widths
    local max_name=5   # "Cache"
    local max_size=4   # "Size"
    local i

    for ((i = 0; i < _SIZE_COUNT; i++)); do
        local name_len=${#_SIZE_NAMES[$i]}
        [[ $name_len -gt $max_name ]] && max_name=$name_len

        local human
        human=$(bytes_to_human "${_SIZE_BYTES[$i]}")
        local size_len=${#human}
        [[ $size_len -gt $max_size ]] && max_size=$size_len
    done

    # Also account for "Total" in name column
    [[ 5 -gt $max_name ]] && max_name=5

    # Compute total for the footer
    local total_bytes=0
    for ((i = 0; i < _SIZE_COUNT; i++)); do
        total_bytes=$((total_bytes + _SIZE_BYTES[i]))
    done
    local total_human
    total_human=$(bytes_to_human "$total_bytes")
    local total_len=${#total_human}
    [[ $total_len -gt $max_size ]] && max_size=$total_len

    # Header
    printf "  %-${max_name}s  %${max_size}s  %s\n" "Cache" "Size" "Path"
    # Separator
    local sep_name sep_size
    sep_name=$(printf '%*s' "$max_name" '' | tr ' ' '-')
    sep_size=$(printf '%*s' "$max_size" '' | tr ' ' '-')
    printf "  %s  %s  %s\n" "$sep_name" "$sep_size" "----"

    # Rows
    for ((i = 0; i < _SIZE_COUNT; i++)); do
        local human
        human=$(bytes_to_human "${_SIZE_BYTES[$i]}")
        # Shorten path: replace $HOME with ~
        local display_path="${_SIZE_PATHS[$i]/#$HOME/~}"
        printf "  %-${max_name}s  %${max_size}s  %s\n" "${_SIZE_NAMES[$i]}" "$human" "$display_path"
    done

    # Total separator + total row
    printf "  %s  %s  %s\n" "$sep_name" "$sep_size" "----"
    printf "  %-${max_name}s  %${max_size}s\n" "Total" "$total_human"
}

# ============================================================================
# Output: JSON
# ============================================================================

_print_json() {
    local total_bytes=0
    local i

    for ((i = 0; i < _SIZE_COUNT; i++)); do
        total_bytes=$((total_bytes + _SIZE_BYTES[i]))
    done

    printf '{\n'
    printf '  "caches": [\n'
    for ((i = 0; i < _SIZE_COUNT; i++)); do
        local comma=","
        [[ $((i + 1)) -eq $_SIZE_COUNT ]] && comma=""
        # Escape backslashes and double quotes in path/name for JSON safety
        local safe_name="${_SIZE_NAMES[$i]//\\/\\\\}"
        safe_name="${safe_name//\"/\\\"}"
        local safe_path="${_SIZE_PATHS[$i]//\\/\\\\}"
        safe_path="${safe_path//\"/\\\"}"
        local human
        human=$(bytes_to_human "${_SIZE_BYTES[$i]}")
        printf '    {"name": "%s", "size_bytes": %s, "size_human": "%s", "path": "%s"}%s\n' \
            "$safe_name" "${_SIZE_BYTES[$i]}" "$human" "$safe_path" "$comma"
    done
    printf '  ],\n'
    printf '  "total_bytes": %s,\n' "$total_bytes"
    printf '  "total_human": "%s"\n' "$(bytes_to_human "$total_bytes")"
    printf '}\n'
}

# ============================================================================
# Help
# ============================================================================

show_size_help() {
    echo "Usage: mo size [OPTIONS]"
    echo ""
    echo "Show developer tool cache sizes sorted by disk usage."
    echo ""
    echo "Options:"
    echo "  --json          Output as JSON"
    echo "  -h, --help      Show this help message"
}

# ============================================================================
# Main
# ============================================================================

size_main() {
    local json_mode=false

    for arg in "$@"; do
        case "$arg" in
            "--help" | "-h")
                show_size_help
                return 0
                ;;
            "--json")
                json_mode=true
                ;;
        esac
    done

    _collect_cache_sizes

    if [[ $_SIZE_COUNT -eq 0 ]]; then
        if [[ "$json_mode" == "true" ]]; then
            printf '{\n  "caches": [],\n  "total_bytes": 0,\n  "total_human": "0B"\n}\n'
        else
            echo ""
            echo "  No developer caches found."
            echo ""
        fi
        return 0
    fi

    _sort_by_size_desc

    if [[ "$json_mode" == "true" ]]; then
        _print_json
    else
        echo ""
        _print_table
        echo ""
    fi
}
