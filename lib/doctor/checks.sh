#!/bin/bash
# Mole - Doctor Command
# Report-only health check for developer environment
# Checks tools, configuration, and system health without modifying anything

set -euo pipefail
export LC_ALL=C

# Prevent multiple sourcing
if [[ -n "${MOLE_DOCTOR_LOADED:-}" ]]; then
    return 0
fi
readonly MOLE_DOCTOR_LOADED=1

# ============================================================================
# Result Tracking
# ============================================================================

# Parallel arrays for check results (Bash 3.2 compatible - no associative arrays)
declare -a DOCTOR_CHECK_NAMES=()
declare -a DOCTOR_CHECK_STATUSES=()
declare -a DOCTOR_CHECK_MESSAGES=()
declare -a DOCTOR_CHECK_HINTS=()

# Record a check result
# Args: $1=name $2=status(pass|warn|fail) $3=message $4=hint(optional)
record_check() {
    local name="$1"
    local check_status="$2"
    local message="$3"
    local hint="${4:-}"

    DOCTOR_CHECK_NAMES+=("$name")
    DOCTOR_CHECK_STATUSES+=("$check_status")
    DOCTOR_CHECK_MESSAGES+=("$message")
    DOCTOR_CHECK_HINTS+=("$hint")
}

# Reset all check results
reset_checks() {
    DOCTOR_CHECK_NAMES=()
    DOCTOR_CHECK_STATUSES=()
    DOCTOR_CHECK_MESSAGES=()
    DOCTOR_CHECK_HINTS=()
}

# ============================================================================
# Individual Checks
# ============================================================================

# Check 1: Xcode Command Line Tools
check_xcode_clt() {
    local clt_path=""
    if clt_path=$(xcode-select -p 2>/dev/null) && [[ -n "$clt_path" && -d "$clt_path" ]]; then
        record_check "Xcode CLT" "pass" "Command Line Tools installed" ""
    else
        record_check "Xcode CLT" "fail" "Command Line Tools not found" \
            "Run: xcode-select --install"
    fi
}

# Check 2: Broken symlinks in PATH
check_path_symlinks() {
    local -a broken_links=()
    local dir=""
    local remaining_path="${PATH:-}"

    # Split PATH on colon (Bash 3.2 compatible, no set --)
    while [[ -n "$remaining_path" ]]; do
        dir="${remaining_path%%:*}"
        if [[ "$remaining_path" == *":"* ]]; then
            remaining_path="${remaining_path#*:}"
        else
            remaining_path=""
        fi

        # Skip empty or nonexistent directories
        [[ -z "$dir" || ! -d "$dir" ]] && continue

        # Find broken symlinks in this directory
        local entry=""
        for entry in "$dir"/*; do
            # Skip glob that matched nothing
            [[ "$entry" == "$dir/*" ]] && continue
            # Check if it is a symlink and its target is missing
            if [[ -L "$entry" && ! -e "$entry" ]]; then
                broken_links+=("$entry")
            fi
        done
    done

    if [[ ${#broken_links[@]} -eq 0 ]]; then
        record_check "PATH symlinks" "pass" "No broken symlinks in PATH" ""
    else
        local count=${#broken_links[@]}
        local sample="${broken_links[0]}"
        local basename_sample="${sample##*/}"
        local detail="${count} broken symlink"
        if [[ $count -gt 1 ]]; then
            detail="${count} broken symlinks"
        fi
        record_check "PATH symlinks" "warn" "${detail} found (e.g. ${basename_sample})" \
            "Remove with: rm \"${sample}\""
    fi
}

# Check 3: Git identity
check_git_identity() {
    if ! command -v git >/dev/null 2>&1; then
        record_check "Git identity" "warn" "git not installed" \
            "Install git via Xcode CLT or Homebrew"
        return
    fi

    local git_name=""
    local git_email=""
    git_name=$(git config --global user.name 2>/dev/null || echo "")
    git_email=$(git config --global user.email 2>/dev/null || echo "")

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        record_check "Git identity" "pass" "Global identity configured (${git_name})" ""
    else
        local missing=""
        if [[ -z "$git_name" && -z "$git_email" ]]; then
            missing="user.name and user.email"
        elif [[ -z "$git_name" ]]; then
            missing="user.name"
        else
            missing="user.email"
        fi
        record_check "Git identity" "fail" "${missing} not set" \
            "Run: git config --global user.name \"Your Name\" && git config --global user.email \"you@example.com\""
    fi
}

# Check 4: Python version
check_python_version() {
    if ! command -v python3 >/dev/null 2>&1; then
        record_check "Python" "warn" "python3 not found" \
            "Install via: brew install python3"
        return
    fi

    local py_version=""
    py_version=$(python3 --version 2>/dev/null | awk '{print $2}' || echo "")
    if [[ -n "$py_version" ]]; then
        record_check "Python" "pass" "python3 ${py_version}" ""
    else
        record_check "Python" "warn" "python3 found but version unknown" ""
    fi
}

# Check 5: Node version
check_node_version() {
    if ! command -v node >/dev/null 2>&1; then
        record_check "Node.js" "warn" "node not found" \
            "Install via: brew install node"
        return
    fi

    local node_version=""
    node_version=$(node --version 2>/dev/null || echo "")
    if [[ -n "$node_version" ]]; then
        record_check "Node.js" "pass" "node ${node_version}" ""
    else
        record_check "Node.js" "warn" "node found but version unknown" ""
    fi
}

# Check 6: Homebrew doctor summary
check_brew_health() {
    if ! command -v brew >/dev/null 2>&1; then
        record_check "Homebrew" "warn" "brew not installed" \
            "Install from: https://brew.sh"
        return
    fi

    local brew_output=""
    local brew_status=0
    brew_output=$(brew doctor 2>&1) || brew_status=$?

    if [[ $brew_status -eq 0 ]]; then
        record_check "Homebrew" "pass" "System ready to brew" ""
    else
        # Count warning lines
        local warning_count=0
        warning_count=$(printf '%s\n' "$brew_output" | grep -c "^Warning:" || true)
        if [[ $warning_count -gt 0 ]]; then
            record_check "Homebrew" "warn" "${warning_count} warning(s) from brew doctor" \
                "Run: brew doctor"
        else
            record_check "Homebrew" "warn" "brew doctor reported issues" \
                "Run: brew doctor"
        fi
    fi
}

# Check 7: Disk SMART status
check_disk_smart() {
    if ! command -v diskutil >/dev/null 2>&1; then
        record_check "Disk SMART" "warn" "diskutil not available" ""
        return
    fi

    local smart_output=""
    smart_output=$(diskutil info disk0 2>/dev/null | grep "SMART Status" || echo "")

    if [[ -z "$smart_output" ]]; then
        record_check "Disk SMART" "warn" "SMART status not available" \
            "Your disk may not support SMART monitoring"
        return
    fi

    if [[ "$smart_output" == *"Verified"* ]]; then
        record_check "Disk SMART" "pass" "Disk health verified" ""
    elif [[ "$smart_output" == *"Failing"* ]]; then
        record_check "Disk SMART" "fail" "Disk SMART status: Failing" \
            "Back up your data immediately and consider replacing the disk"
    else
        local status_text=""
        status_text=$(printf '%s' "$smart_output" | sed 's/.*SMART Status:[[:space:]]*//')
        record_check "Disk SMART" "warn" "Disk SMART status: ${status_text}" ""
    fi
}

# ============================================================================
# Output Formatters
# ============================================================================

# Print human-readable checklist
print_checklist() {
    echo ""
    echo -e "${PURPLE_BOLD}Developer Environment Health Check${NC}"
    echo ""

    local i=0
    local total=${#DOCTOR_CHECK_NAMES[@]}
    local pass_count=0
    local warn_count=0
    local fail_count=0

    while [[ $i -lt $total ]]; do
        local name="${DOCTOR_CHECK_NAMES[$i]}"
        local check_status="${DOCTOR_CHECK_STATUSES[$i]}"
        local message="${DOCTOR_CHECK_MESSAGES[$i]}"
        local hint="${DOCTOR_CHECK_HINTS[$i]}"

        case "$check_status" in
            pass)
                printf "  ${GREEN}${ICON_SUCCESS}${NC} %-14s %s\n" "$name" "$message"
                ((pass_count++)) || true
                ;;
            warn)
                printf "  ${YELLOW}${ICON_WARNING}${NC} %-14s ${YELLOW}%s${NC}\n" "$name" "$message"
                ((warn_count++)) || true
                if [[ -n "$hint" ]]; then
                    printf "    ${GRAY}${ICON_SUBLIST} %s${NC}\n" "$hint"
                fi
                ;;
            fail)
                printf "  ${RED}${ICON_ERROR}${NC} %-14s ${RED}%s${NC}\n" "$name" "$message"
                ((fail_count++)) || true
                if [[ -n "$hint" ]]; then
                    printf "    ${GRAY}${ICON_SUBLIST} %s${NC}\n" "$hint"
                fi
                ;;
        esac

        ((i++)) || true
    done

    echo ""
    local summary="${pass_count} passed"
    if [[ $warn_count -gt 0 ]]; then
        summary="${summary}, ${warn_count} warning(s)"
    fi
    if [[ $fail_count -gt 0 ]]; then
        summary="${summary}, ${fail_count} failed"
    fi
    echo -e "  ${GRAY}${summary}${NC}"
    echo ""
}

# Print JSON output
print_json() {
    local i=0
    local total=${#DOCTOR_CHECK_NAMES[@]}

    echo "{"
    echo "  \"checks\": ["

    while [[ $i -lt $total ]]; do
        local name="${DOCTOR_CHECK_NAMES[$i]}"
        local check_status="${DOCTOR_CHECK_STATUSES[$i]}"
        local message="${DOCTOR_CHECK_MESSAGES[$i]}"
        local hint="${DOCTOR_CHECK_HINTS[$i]}"

        # JSON-escape strings (backslash and double quote)
        name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
        check_status=$(printf '%s' "$check_status" | sed 's/\\/\\\\/g; s/"/\\"/g')
        message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
        hint=$(printf '%s' "$hint" | sed 's/\\/\\\\/g; s/"/\\"/g')

        local comma=""
        if [[ $((i + 1)) -lt $total ]]; then
            comma=","
        fi

        if [[ -n "$hint" ]]; then
            cat <<EOF
    {
      "name": "${name}",
      "status": "${check_status}",
      "message": "${message}",
      "hint": "${hint}"
    }${comma}
EOF
        else
            cat <<EOF
    {
      "name": "${name}",
      "status": "${check_status}",
      "message": "${message}"
    }${comma}
EOF
        fi

        ((i++)) || true
    done

    echo "  ]"
    echo "}"
}

# ============================================================================
# Help
# ============================================================================

show_doctor_help() {
    echo "Usage: mo doctor [OPTIONS]"
    echo ""
    echo "Check developer environment health (report only, no changes)."
    echo ""
    echo "Checks:"
    echo "  - Xcode Command Line Tools installation"
    echo "  - Broken symlinks in PATH"
    echo "  - Git global identity (user.name, user.email)"
    echo "  - Python 3 availability"
    echo "  - Node.js availability"
    echo "  - Homebrew doctor summary"
    echo "  - Disk SMART health status"
    echo ""
    echo "Options:"
    echo "  --json            Output results as JSON"
    echo "  -h, --help        Show this help message"
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    local json_mode=false

    for arg in "$@"; do
        case "$arg" in
            "--help" | "-h")
                show_doctor_help
                return 0
                ;;
            "--json")
                json_mode=true
                ;;
        esac
    done

    reset_checks

    # Run all checks
    check_xcode_clt
    check_path_symlinks
    check_git_identity
    check_python_version
    check_node_version
    check_brew_health
    check_disk_smart

    # Output results
    if [[ "$json_mode" == "true" ]]; then
        print_json
    else
        print_checklist
    fi

    return 0
}
