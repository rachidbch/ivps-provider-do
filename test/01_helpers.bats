#!/usr/bin/env bats
# Unit tests for DO plugin helper functions

load helpers/common

setup() {
    _setup_do_env
    _setup_do_stubs
    source_plugin_functions
}

teardown() {
    _teardown_do_env
}

# --- require_token ---

@test "require_token: fails when DO_API_TOKEN unset" {
    unset DO_API_TOKEN
    run require_token
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "not set"
}

@test "require_token: fails when DO_API_TOKEN empty" {
    export DO_API_TOKEN=""
    run require_token
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "not set"
}

@test "require_token: succeeds with valid token" {
    export DO_API_TOKEN="test-fake-token-12345"
    run require_token
    [ "$status" -eq 0 ]
}

# --- require_doctl ---

@test "require_doctl: fails when doctl not in PATH (exit 4)" {
    export DO_API_TOKEN="test-fake-token-12345"
    # Remove doctl from PATH by creating a clean stub dir without it
    local clean_dir="$DO_TEST_TMPDIR/clean_stubs"
    mkdir -p "$clean_dir"
    # Put essentials (jq, envsubst, rm, etc.) but NOT doctl
    if command -v jq &>/dev/null; then
        ln -sf "$(command -v jq)" "$clean_dir/jq"
    fi
    if command -v envsubst &>/dev/null; then
        ln -sf "$(command -v envsubst)" "$clean_dir/envsubst"
    fi
    # Save original PATH and restore after
    local saved_path="$PATH"
    export PATH="$clean_dir"
    run require_doctl
    export PATH="$saved_path"
    [ "$status" -eq 4 ]
    echo "$output" | grep -q "doctl"
}

@test "require_doctl: succeeds when doctl is available" {
    export DO_API_TOKEN="test-fake-token-12345"
    # Create a fake doctl in the stub dir
    echo '#!/bin/bash' > "$DO_TEST_TMPDIR/stubs/doctl"
    echo 'echo "doctl stub"' >> "$DO_TEST_TMPDIR/stubs/doctl"
    chmod +x "$DO_TEST_TMPDIR/stubs/doctl"
    export PATH="$DO_TEST_TMPDIR/stubs:$PATH"
    run require_doctl
    [ "$status" -eq 0 ]
}

# --- cmd_keys ---

@test "cmd_keys: outputs DO_API_TOKEN key line" {
    run cmd_keys
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "DO_API_TOKEN:DigitalOcean API Token"
}
