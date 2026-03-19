#!/bin/bash
# Mole - Schedule Manager
# Install/remove LaunchAgent for periodic maintenance health checks

set -euo pipefail
export LC_ALL=C

readonly SCHEDULE_LABEL="fun.tw93.mole.maintenance"
readonly SCHEDULE_PLIST_PATH="$HOME/Library/LaunchAgents/${SCHEDULE_LABEL}.plist"
readonly SCHEDULE_DEFAULT_INTERVAL=604800 # Weekly (7 days)
readonly SCHEDULE_LOG_DIR="$HOME/Library/Logs/mole"

# ============================================================================
# Plist Generation
# ============================================================================

generate_plist() {
    local mole_path="$1"
    local interval="$2"
    local home_dir="$HOME"

    cat <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SCHEDULE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${mole_path}</string>
        <string>clean</string>
        <string>--dry-run</string>
    </array>
    <key>StartInterval</key>
    <integer>${interval}</integer>
    <key>StandardOutPath</key>
    <string>${home_dir}/Library/Logs/mole/schedule.log</string>
    <key>StandardErrorPath</key>
    <string>${home_dir}/Library/Logs/mole/schedule-error.log</string>
</dict>
</plist>
PLIST_EOF
}

# ============================================================================
# Interval Formatting
# ============================================================================

format_interval_human() {
    local seconds="${1:-0}"
    [[ ! "$seconds" =~ ^[0-9]+$ ]] && seconds=0

    if [[ "$seconds" -lt 60 ]]; then
        echo "${seconds} seconds"
    elif [[ "$seconds" -lt 3600 ]]; then
        local minutes=$((seconds / 60))
        [[ "$minutes" -eq 1 ]] && echo "1 minute" || echo "${minutes} minutes"
    elif [[ "$seconds" -lt 86400 ]]; then
        local hours=$((seconds / 3600))
        [[ "$hours" -eq 1 ]] && echo "1 hour" || echo "${hours} hours"
    elif [[ "$seconds" -lt 604800 ]]; then
        local days=$((seconds / 86400))
        [[ "$days" -eq 1 ]] && echo "1 day" || echo "${days} days"
    else
        local weeks=$((seconds / 604800))
        [[ "$weeks" -eq 1 ]] && echo "1 week" || echo "${weeks} weeks"
    fi
}

# ============================================================================
# Mole Path Detection
# ============================================================================

detect_mole_path() {
    local mole_path=""
    mole_path=$(command -v mole 2>/dev/null || true)
    if [[ -z "$mole_path" ]]; then
        mole_path=$(command -v mo 2>/dev/null || true)
    fi
    if [[ -z "$mole_path" ]]; then
        # Fallback: try relative to this script
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local candidate="${script_dir}/../../mole"
        if [[ -x "$candidate" ]]; then
            mole_path="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
        fi
    fi
    echo "$mole_path"
}

# ============================================================================
# Subcommands
# ============================================================================

schedule_install() {
    local dry_run=false
    local interval="$SCHEDULE_DEFAULT_INTERVAL"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run | -n)
                dry_run=true
                shift
                ;;
            --interval)
                if [[ $# -lt 2 ]]; then
                    log_error "Missing value for --interval"
                    return 1
                fi
                interval="$2"
                if [[ ! "$interval" =~ ^[0-9]+$ ]] || [[ "$interval" -eq 0 ]]; then
                    log_error "Invalid interval: $interval (must be a positive integer)"
                    return 1
                fi
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    local mole_path
    mole_path=$(detect_mole_path)
    if [[ -z "$mole_path" ]]; then
        log_error "Could not find mole binary. Ensure mole is in PATH."
        return 1
    fi

    local plist_content
    plist_content=$(generate_plist "$mole_path" "$interval")

    if [[ "$dry_run" == "true" ]]; then
        echo -e "${YELLOW}${ICON_DRY_RUN} DRY RUN${NC}, would install LaunchAgent:"
        echo ""
        echo -e "${GRAY}Path: ${SCHEDULE_PLIST_PATH}${NC}"
        echo -e "${GRAY}Interval: $(format_interval_human "$interval")${NC}"
        echo ""
        echo "$plist_content"
        return 0
    fi

    # Ensure log directory exists
    ensure_user_dir "$SCHEDULE_LOG_DIR"

    # Ensure LaunchAgents directory exists
    ensure_user_dir "$HOME/Library/LaunchAgents"

    # Unload existing agent if present
    if [[ -f "$SCHEDULE_PLIST_PATH" ]]; then
        launchctl bootout "gui/$(id -u)" "$SCHEDULE_PLIST_PATH" 2>/dev/null || true
    fi

    # Write plist
    echo "$plist_content" > "$SCHEDULE_PLIST_PATH"

    # Load the agent
    launchctl bootstrap "gui/$(id -u)" "$SCHEDULE_PLIST_PATH" 2>/dev/null || true

    log_success "LaunchAgent installed, schedule: every $(format_interval_human "$interval")"
    echo -e "  ${GRAY}${ICON_SUBLIST} ${SCHEDULE_PLIST_PATH}${NC}"
}

schedule_remove() {
    if [[ ! -f "$SCHEDULE_PLIST_PATH" ]]; then
        echo -e "${YELLOW}${ICON_WARNING}${NC} LaunchAgent not installed"
        return 0
    fi

    # Unload the agent
    launchctl bootout "gui/$(id -u)" "$SCHEDULE_PLIST_PATH" 2>/dev/null || true

    # Remove the plist file
    rm -f "$SCHEDULE_PLIST_PATH"

    log_success "LaunchAgent removed"
}

schedule_status() {
    if [[ ! -f "$SCHEDULE_PLIST_PATH" ]]; then
        echo -e "${YELLOW}${ICON_WARNING}${NC} LaunchAgent not installed"
        return 0
    fi

    echo -e "${GREEN}${ICON_SUCCESS}${NC} LaunchAgent installed"
    echo -e "  ${GRAY}${ICON_SUBLIST} ${SCHEDULE_PLIST_PATH}${NC}"

    # Extract interval from plist
    local interval=""
    interval=$(sed -n '/<key>StartInterval<\/key>/{n;s/.*<integer>\([0-9]*\)<\/integer>.*/\1/p;}' "$SCHEDULE_PLIST_PATH" 2>/dev/null || true)
    if [[ -n "$interval" ]]; then
        echo -e "  ${GRAY}${ICON_SUBLIST} Interval: $(format_interval_human "$interval")${NC}"
    fi

    # Check if loaded
    if launchctl list 2>/dev/null | grep -q "$SCHEDULE_LABEL"; then
        echo -e "  ${GREEN}${ICON_SUCCESS}${NC} Agent is loaded and active"
    else
        echo -e "  ${YELLOW}${ICON_WARNING}${NC} Agent is not currently loaded"
    fi
}

# ============================================================================
# Help
# ============================================================================

show_schedule_help() {
    echo "Usage: mo schedule <command> [OPTIONS]"
    echo ""
    echo "Install or remove a LaunchAgent for periodic maintenance checks."
    echo ""
    echo "Commands:"
    echo "  install             Install the LaunchAgent plist"
    echo "  remove              Remove the LaunchAgent plist"
    echo "  status              Show current schedule status"
    echo ""
    echo "Install options:"
    echo "  --dry-run, -n       Show plist without installing"
    echo "  --interval <secs>   Set check interval (default: 604800 = weekly)"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
}

# ============================================================================
# Main
# ============================================================================

main() {
    local command=""

    if [[ $# -eq 0 ]]; then
        show_schedule_help
        return 0
    fi

    for arg in "$@"; do
        case "$arg" in
            --help | -h)
                show_schedule_help
                return 0
                ;;
        esac
    done

    command="$1"
    shift

    case "$command" in
        install)
            schedule_install "$@"
            ;;
        remove)
            schedule_remove
            ;;
        status)
            schedule_status
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_schedule_help
            return 1
            ;;
    esac
}
