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

# --- load_provider_config ---

@test "load_provider_config: returns 2 when config missing" {
    run load_provider_config
    [ "$status" -eq 2 ]
}

@test "load_provider_config: succeeds when config exists" {
    _write_provider_config
    load_provider_config
    [ "$DO_API_TOKEN" = "test-fake-token-12345" ]
}

# --- require_token ---

@test "require_token: fails when config missing" {
    run require_token
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "not configured"
}

@test "require_token: fails when token empty" {
    _write_provider_config ""
    run require_token
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "not set"
}

@test "require_token: succeeds with valid token" {
    _write_provider_config
    run require_token
    [ "$status" -eq 0 ]
}

# --- do_api ---

@test "do_api: calls curl with correct auth header" {
    _write_provider_config
    require_token
    run do_api GET /account
    [ "$status" -eq 0 ]
}

@test "do_api: GET passes through curl response" {
    _write_provider_config
    require_token
    _set_curl_response '{"account":{"email":"test@example.com"}}'
    run do_api GET /account
    echo "$output" | grep -q "test@example.com"
}

@test "do_api: DELETE method" {
    _write_provider_config
    require_token
    _set_curl_response ''
    run do_api DELETE /droplets/123
    [ "$status" -eq 0 ]
}
