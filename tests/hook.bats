#!/usr/bin/env bats

setup_file() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    export PROJECT_ROOT

    ORIGINAL_HOME="${HOME:-}"
    export ORIGINAL_HOME

    ORIGINAL_PATH="${PATH:-}"
    export ORIGINAL_PATH

    HOME="$(mktemp -d "${BATS_TEST_DIRNAME}/tmp-hook-home.XXXXXX")"
    export HOME

    mkdir -p "$HOME"

    PATH="$PROJECT_ROOT:$PATH"
    export PATH
}

teardown_file() {
    rm -rf "$HOME"
    if [[ -n "${ORIGINAL_HOME:-}" ]]; then
        export HOME="$ORIGINAL_HOME"
    fi
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="$ORIGINAL_PATH"
    fi
}

setup() {
    rm -rf "${HOME:?}"/.zshrc "${HOME:?}"/.bashrc "${HOME:?}"/.bash_profile
    rm -rf "${HOME:?}"/.config
    mkdir -p "$HOME"
}

@test "hook script exists and is executable" {
    [ -f "$PROJECT_ROOT/bin/hook.sh" ]
    [ -x "$PROJECT_ROOT/bin/hook.sh" ]
}

@test "hook script has valid bash syntax" {
    run bash -n "$PROJECT_ROOT/bin/hook.sh"
    [ "$status" -eq 0 ]
}

@test "hook --help shows usage" {
    run "$PROJECT_ROOT/bin/hook.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mole hook"* ]]
    [[ "$output" == *"bash"* ]]
    [[ "$output" == *"zsh"* ]]
    [[ "$output" == *"fish"* ]]
    [[ "$output" == *"install"* ]]
}

@test "hook bash generates valid bash script" {
    run "$PROJECT_ROOT/bin/hook.sh" bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"__mole_cd_hook"* ]]
    [[ "$output" == *"PROMPT_COMMAND"* ]]
    [[ "$output" == *"node_modules"* ]]
}

@test "hook bash script detects node_modules reference" {
    run "$PROJECT_ROOT/bin/hook.sh" bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"node_modules"* ]]
    [[ "$output" == *"mo purge"* ]]
}

@test "hook bash script can be parsed by bash" {
    run bash -n <("$PROJECT_ROOT/bin/hook.sh" bash)
    [ "$status" -eq 0 ]
}

@test "hook zsh generates valid zsh script" {
    run "$PROJECT_ROOT/bin/hook.sh" zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"__mole_cd_hook"* ]]
    [[ "$output" == *"chpwd"* ]]
    [[ "$output" == *"node_modules"* ]]
}

@test "hook zsh uses chpwd hook mechanism" {
    run "$PROJECT_ROOT/bin/hook.sh" zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"add-zsh-hook"* ]] || [[ "$output" == *"chpwd_functions"* ]]
}

@test "hook fish generates valid fish script" {
    run "$PROJECT_ROOT/bin/hook.sh" fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"__mole_cd_hook"* ]]
    [[ "$output" == *"--on-variable PWD"* ]]
    [[ "$output" == *"node_modules"* ]]
}

@test "hook fish uses PWD variable hook" {
    run "$PROJECT_ROOT/bin/hook.sh" fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"--on-variable PWD"* ]]
}

@test "hook with no args shows usage" {
    run "$PROJECT_ROOT/bin/hook.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: mole hook"* ]]
}

@test "hook unknown subcommand fails" {
    run "$PROJECT_ROOT/bin/hook.sh" invalid-shell
    [ "$status" -ne 0 ]
}

@test "hook bash includes 500MB threshold check" {
    run "$PROJECT_ROOT/bin/hook.sh" bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"512000"* ]]
}

@test "hook zsh includes 500MB threshold check" {
    run "$PROJECT_ROOT/bin/hook.sh" zsh
    [ "$status" -eq 0 ]
    [[ "$output" == *"512000"* ]]
}

@test "hook fish includes 500MB threshold check" {
    run "$PROJECT_ROOT/bin/hook.sh" fish
    [ "$status" -eq 0 ]
    [[ "$output" == *"512000"* ]]
}

@test "hook subcommand supports bash/zsh/fish" {
    run "$PROJECT_ROOT/bin/hook.sh" bash
    [ "$status" -eq 0 ]

    run "$PROJECT_ROOT/bin/hook.sh" zsh
    [ "$status" -eq 0 ]

    run "$PROJECT_ROOT/bin/hook.sh" fish
    [ "$status" -eq 0 ]
}

@test "hook install detects zsh" {
    export SHELL=/bin/zsh

    run "$PROJECT_ROOT/bin/hook.sh" install

    if [[ "$output" == *"not found in PATH"* ]]; then
        skip "mole not found in PATH during test"
    fi

    [ "$status" -eq 0 ]
    [[ "$output" == *"hook"* ]]
}

@test "hook bash script defines __mole_hook_installed guard" {
    run "$PROJECT_ROOT/bin/hook.sh" bash
    [ "$status" -eq 0 ]
    [[ "$output" == *"__mole_hook_installed"* ]]
}

@test "exit status is 0 for all shell outputs" {
    run "$PROJECT_ROOT/bin/hook.sh" bash
    [ "$status" -eq 0 ]

    run "$PROJECT_ROOT/bin/hook.sh" zsh
    [ "$status" -eq 0 ]

    run "$PROJECT_ROOT/bin/hook.sh" fish
    [ "$status" -eq 0 ]

    run "$PROJECT_ROOT/bin/hook.sh" --help
    [ "$status" -eq 0 ]
}
