#!/bin/bash
# Mole - Log Viewer
# Human-friendly viewer for operations.log

set -euo pipefail
export LC_ALL=C

# Prevent multiple sourcing
if [[ -n "${MOLE_LOG_VIEWER_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_LOG_VIEWER_LOADED=1

# ============================================================================
# Log Viewer Configuration
# ============================================================================

# OPERATIONS_LOG_FILE is defined as readonly in lib/core/log.sh (sourced via common.sh).
# Fall back only if not already set (e.g., standalone usage).
if [[ -z "${OPERATIONS_LOG_FILE:-}" ]]; then
    OPERATIONS_LOG_FILE="${HOME}/Library/Logs/mole/operations.log"
fi

# ============================================================================
# Help
# ============================================================================

show_log_help() {
    echo "Usage: mo log [OPTIONS]"
    echo ""
    echo "View Mole operations log in a human-friendly format."
    echo ""
    echo "Options:"
    echo "  --since <duration>  Show entries newer than duration (e.g., 7d, 24h, 30m)"
    echo "  --grep <pattern>   Filter entries matching pattern (case-insensitive)"
    echo "  --tail <N>         Show last N entries (default: show all)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  mo log                  Show all log entries"
    echo "  mo log --since 7d       Show entries from the last 7 days"
    echo "  mo log --grep clean     Show only cleanup entries"
    echo "  mo log --tail 20        Show the last 20 entries"
}

# ============================================================================
# Duration Parsing
# ============================================================================

# Parse a duration string (e.g., "7d", "24h", "30m") into seconds
# Returns the number of seconds, or empty string on failure
parse_duration_to_seconds() {
    local duration="$1"
    local value=""
    local unit=""

    # Extract numeric value and unit
    value="${duration%[dhm]*}"
    unit="${duration#"$value"}"

    # Validate numeric value
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo ""
        return 1
    fi

    case "$unit" in
        d) echo "$((value * 86400))" ;;
        h) echo "$((value * 3600))" ;;
        m) echo "$((value * 60))" ;;
        *)
            echo ""
            return 1
            ;;
    esac
}

# ============================================================================
# Timestamp Parsing
# ============================================================================

# Parse a log timestamp string to epoch seconds (BSD date)
# Input: "2024-03-15 10:30:45"
# Returns epoch seconds or empty string on failure
parse_log_timestamp() {
    local timestamp="$1"
    local epoch=""

    # BSD date: -j prevents setting date, -f specifies input format
    epoch=$(date -j -f "%Y-%m-%d %H:%M:%S" "$timestamp" "+%s" 2>/dev/null || echo "")

    echo "$epoch"
}

# ============================================================================
# Line Formatting
# ============================================================================

# Format a single log line with colors
# Input: raw log line like "[2024-03-15 10:30:45] [clean] REMOVED /path (detail)"
format_log_line() {
    local line="$1"

    # Extract components using parameter expansion (Bash 3.2 compatible)
    # Format: [TIMESTAMP] [COMMAND] ACTION PATH (DETAIL)

    # Extract timestamp: everything between first [ and ]
    local timestamp_part="${line#\[}"
    timestamp_part="${timestamp_part%%\]*}"

    # After timestamp, extract command: next [...]
    local after_ts="${line#*\] }"
    local command_part="${after_ts#\[}"
    command_part="${command_part%%\]*}"

    # After command, extract action, path, and optional detail
    local after_cmd="${after_ts#*\] }"
    local action="${after_cmd%% *}"
    local path_and_detail="${after_cmd#* }"

    local path=""
    local detail=""

    # Check if there's a parenthesized detail at the end
    case "$path_and_detail" in
        *" ("*")")
            # Has detail in parentheses
            detail="${path_and_detail##* (}"
            detail="${detail%)}"
            path="${path_and_detail% (*}"
            ;;
        *)
            path="$path_and_detail"
            ;;
    esac

    # Color-code the action
    local action_color=""
    case "$action" in
        REMOVED)  action_color="${GREEN}" ;;
        SKIPPED)  action_color="${YELLOW}" ;;
        FAILED)   action_color="${RED}" ;;
        REBUILT)  action_color="${BLUE}" ;;
        *)        action_color="${NC}" ;;
    esac

    # Build formatted output
    local formatted="${GRAY}${timestamp_part}${NC}"
    formatted+="  ${GRAY}[${command_part}]${NC}"
    formatted+="  ${action_color}${action}${NC}"
    formatted+="  ${path}"
    if [[ -n "$detail" ]]; then
        formatted+="  ${GRAY}${detail}${NC}"
    fi

    echo -e "$formatted"
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    local since_seconds=""
    local grep_pattern=""
    local tail_count=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help | -h)
                show_log_help
                return 0
                ;;
            --since)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --since requires a duration argument (e.g., 7d, 24h, 30m)" >&2
                    return 1
                fi
                since_seconds=$(parse_duration_to_seconds "$2")
                if [[ -z "$since_seconds" ]]; then
                    echo "Error: Invalid duration format: $2 (use e.g., 7d, 24h, 30m)" >&2
                    return 1
                fi
                shift 2
                ;;
            --grep)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --grep requires a pattern argument" >&2
                    return 1
                fi
                grep_pattern="$2"
                shift 2
                ;;
            --tail)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --tail requires a number argument" >&2
                    return 1
                fi
                tail_count="$2"
                if [[ ! "$tail_count" =~ ^[0-9]+$ ]]; then
                    echo "Error: --tail requires a numeric argument" >&2
                    return 1
                fi
                shift 2
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Use 'mo log --help' for usage information." >&2
                return 1
                ;;
        esac
    done

    # Check if log file exists and has content
    if [[ ! -f "$OPERATIONS_LOG_FILE" ]] || [[ ! -s "$OPERATIONS_LOG_FILE" ]]; then
        echo "No log entries found."
        echo ""
        echo "Operations are logged when you run commands like 'mo clean'."
        echo "Log file: $OPERATIONS_LOG_FILE"
        return 0
    fi

    # Calculate cutoff timestamp if --since was specified
    local cutoff_epoch=""
    if [[ -n "$since_seconds" ]]; then
        local now_epoch
        now_epoch=$(date +%s)
        cutoff_epoch=$((now_epoch - since_seconds))
    fi

    # Read and filter log entries
    local -a filtered_lines=()

    while IFS= read -r line; do
        # Skip blank lines
        [[ -z "$line" ]] && continue

        # Skip comment/session marker lines
        case "$line" in
            "#"*) continue ;;
        esac

        # Must be a log entry line starting with [
        case "$line" in
            "["*) ;;
            *) continue ;;
        esac

        # Apply --since filter
        if [[ -n "$cutoff_epoch" ]]; then
            local ts_part="${line#\[}"
            ts_part="${ts_part%%\]*}"
            local line_epoch
            line_epoch=$(parse_log_timestamp "$ts_part")
            if [[ -z "$line_epoch" ]] || [[ "$line_epoch" -lt "$cutoff_epoch" ]]; then
                continue
            fi
        fi

        # Apply --grep filter (case-insensitive)
        if [[ -n "$grep_pattern" ]]; then
            local lower_line
            local lower_pattern
            # Bash 3.2 compatible case-insensitive match using tr
            lower_line=$(echo "$line" | tr '[:upper:]' '[:lower:]')
            lower_pattern=$(echo "$grep_pattern" | tr '[:upper:]' '[:lower:]')
            case "$lower_line" in
                *"$lower_pattern"*) ;;
                *) continue ;;
            esac
        fi

        filtered_lines+=("$line")
    done < "$OPERATIONS_LOG_FILE"

    # Apply --tail filter
    if [[ -n "$tail_count" ]] && [[ ${#filtered_lines[@]} -gt "$tail_count" ]]; then
        local start_idx=$(( ${#filtered_lines[@]} - tail_count ))
        local -a tail_lines=()
        local i
        for (( i = start_idx; i < ${#filtered_lines[@]}; i++ )); do
            tail_lines+=("${filtered_lines[$i]}")
        done
        filtered_lines=("${tail_lines[@]}")
    fi

    # Check if any entries remain after filtering
    if [[ ${#filtered_lines[@]} -eq 0 ]]; then
        echo "No log entries found."
        return 0
    fi

    # Display formatted entries
    local entry
    for entry in "${filtered_lines[@]}"; do
        format_log_line "$entry"
    done

    return 0
}
