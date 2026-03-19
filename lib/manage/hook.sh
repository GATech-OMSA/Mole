#!/bin/bash
# Mole - Shell Hook Management
# Provides cd hook that alerts on large node_modules / .git directories
set -euo pipefail

# Size threshold in KB (500MB = 512000 KB)
readonly MOLE_HOOK_SIZE_THRESHOLD_KB=512000

# Emit the bash cd hook script to stdout
_hook_emit_bash() {
    cat << 'HOOK_BASH'
__mole_cd_hook() {
    if [[ -d "node_modules" ]]; then
        local size_kb
        size_kb=$(du -sk "node_modules" 2>/dev/null | awk '{print $1}') || size_kb=0
        if [[ "$size_kb" -ge 512000 ]]; then
            local size_mb=$((size_kb / 1024))
            printf '\360\237\222\241 node_modules is %sMB \342\200\224 run `mo purge` to clean\n' "$size_mb"
        fi
    fi
}
if [[ -z "${__mole_hook_installed:-}" ]]; then
    if [[ -n "${PROMPT_COMMAND:-}" ]]; then
        PROMPT_COMMAND="__mole_cd_hook;${PROMPT_COMMAND}"
    else
        PROMPT_COMMAND="__mole_cd_hook"
    fi
    __mole_hook_installed=1
fi
HOOK_BASH
}

# Emit the zsh cd hook script to stdout
_hook_emit_zsh() {
    cat << 'HOOK_ZSH'
__mole_cd_hook() {
    if [[ -d "node_modules" ]]; then
        local size_kb
        size_kb=$(du -sk "node_modules" 2>/dev/null | awk '{print $1}') || size_kb=0
        if [[ "$size_kb" -ge 512000 ]]; then
            local size_mb=$((size_kb / 1024))
            printf '\360\237\222\241 node_modules is %sMB \342\200\224 run `mo purge` to clean\n' "$size_mb"
        fi
    fi
}
if (( ! ${+functions[__mole_cd_hook]} == 0 )); then
    :
fi
autoload -Uz add-zsh-hook 2>/dev/null || true
if (( ${+functions[add-zsh-hook]} )); then
    add-zsh-hook chpwd __mole_cd_hook
else
    chpwd_functions=("${chpwd_functions[@]}" __mole_cd_hook)
fi
HOOK_ZSH
}

# Emit the fish cd hook script to stdout
_hook_emit_fish() {
    cat << 'HOOK_FISH'
function __mole_cd_hook --on-variable PWD
    if test -d "node_modules"
        set -l size_kb (du -sk "node_modules" 2>/dev/null | awk '{print $1}')
        if test "$size_kb" -ge 512000
            set -l size_mb (math "$size_kb / 1024")
            printf '\360\237\222\241 node_modules is %sMB \342\200\224 run `mo purge` to clean\n' "$size_mb"
        end
    end
end
HOOK_FISH
}

# Detect current shell and install the hook into the appropriate config file
_hook_install() {
    local current_shell="${SHELL##*/}"
    if [[ -z "$current_shell" ]]; then
        current_shell="$(ps -p "$PPID" -o comm= 2>/dev/null | awk '{print $1}')"
    fi

    local hook_name=""
    if command -v mole >/dev/null 2>&1; then
        hook_name="mole"
    elif command -v mo >/dev/null 2>&1; then
        hook_name="mo"
    fi

    if [[ -z "$hook_name" ]]; then
        log_error "mole not found in PATH, install Mole before enabling hook"
        return 1
    fi

    local config_file=""
    local hook_line=""
    case "$current_shell" in
        bash)
            config_file="${HOME}/.bashrc"
            [[ -f "${HOME}/.bash_profile" ]] && config_file="${HOME}/.bash_profile"
            # shellcheck disable=SC2016
            hook_line='if output="$('"$hook_name"' hook bash 2>/dev/null)"; then eval "$output"; fi'
            ;;
        zsh)
            config_file="${HOME}/.zshrc"
            # shellcheck disable=SC2016
            hook_line='if output="$('"$hook_name"' hook zsh 2>/dev/null)"; then eval "$output"; fi'
            ;;
        fish)
            config_file="${HOME}/.config/fish/config.fish"
            # shellcheck disable=SC2016
            hook_line='set -l output ('"$hook_name"' hook fish 2>/dev/null); and echo "$output" | source'
            ;;
        *)
            log_error "Unsupported shell: $current_shell"
            echo "  mole hook <bash|zsh|fish>"
            return 1
            ;;
    esac

    # Check if already installed
    if [[ -f "$config_file" ]] && grep -qF "hook" "$config_file" 2>/dev/null && grep -qF "$hook_name" "$config_file" 2>/dev/null; then
        echo -e "${GREEN}${ICON_SUCCESS}${NC} Shell hook already installed in $config_file"
        return 0
    fi

    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        touch "$config_file"
    fi

    # Append the hook line
    {
        echo ""
        echo "# Mole shell hook"
        echo "$hook_line"
    } >> "$config_file"

    echo -e "${GREEN}${ICON_SUCCESS}${NC} Shell hook added to $config_file"
    echo ""
    echo -e "${GRAY}To activate now:${NC}"
    echo -e "  ${GREEN}source $config_file${NC}"
    return 0
}

_hook_usage() {
    cat << 'EOF'
Usage: mole hook [bash|zsh|fish|install]

Setup shell cd hook for directory size warnings.

Subcommands:
  bash       Generate bash hook script
  zsh        Generate zsh hook script
  fish       Generate fish hook script
  install    Auto-detect shell and install hook

The hook runs after each cd and warns when node_modules exceeds 500MB.

Examples:
  # Auto-install (recommended)
  mole hook install

  # Manual install - Bash
  eval "$(mole hook bash)"

  # Manual install - Zsh
  eval "$(mole hook zsh)"

  # Manual install - Fish
  mole hook fish | source
EOF
}

# Main entry point for hook command
hook_main() {
    local subcommand="${1:-}"

    case "$subcommand" in
        bash)
            _hook_emit_bash
            ;;
        zsh)
            _hook_emit_zsh
            ;;
        fish)
            _hook_emit_fish
            ;;
        install)
            _hook_install
            ;;
        --help | -h | "")
            _hook_usage
            ;;
        *)
            log_error "Unknown subcommand: $subcommand"
            _hook_usage
            return 1
            ;;
    esac
}
