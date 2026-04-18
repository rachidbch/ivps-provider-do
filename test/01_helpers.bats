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

# --- do_api ---

@test "do_api: calls curl with correct auth header" {
    export DO_API_TOKEN="test-fake-token-12345"
    run do_api GET /account
    [ "$status" -eq 0 ]
}

@test "do_api: GET passes through curl response" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"account":{"email":"test@example.com"}}'
    run do_api GET /account
    echo "$output" | grep -q "test@example.com"
}

@test "do_api: DELETE method" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response ''
    run do_api DELETE /droplets/123
    [ "$status" -eq 0 ]
}

# --- cmd_keys ---

@test "cmd_keys: outputs DO_API_TOKEN key line" {
    run cmd_keys
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "DO_API_TOKEN:DigitalOcean API Token"
}
