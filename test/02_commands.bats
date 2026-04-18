#!/usr/bin/env bats
# Tests for DO plugin subcommands (validate, create, delete, list, show)

load helpers/common

setup() {
    _setup_do_env
    _setup_do_stubs
    source_plugin_functions
}

teardown() {
    _teardown_do_env
}

# --- cmd_validate ---

@test "cmd_validate: succeeds with valid regions response" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"regions":[{"slug":"nyc1"},{"slug":"sfo3"}],"meta":{"total":2}}'
    run cmd_validate
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Authenticated"
}

@test "cmd_validate: fails with bad response" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"id":"Forbidden","message":"You are not authorized"}'
    run cmd_validate
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Failed to authenticate"
}

@test "cmd_validate: fails without token" {
    unset DO_API_TOKEN
    run cmd_validate
    [ "$status" -eq 2 ]
}

# --- cmd_create ---

@test "cmd_create: fails without name" {
    export DO_API_TOKEN="test-fake-token-12345"
    run cmd_create
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Usage"
}

@test "cmd_create: fails without token" {
    unset DO_API_TOKEN
    run cmd_create "my-node"
    [ "$status" -eq 2 ]
}

@test "cmd_create: returns IPV4/PROVIDER_ID on success" {
    export DO_API_TOKEN="test-fake-token-12345"

    # First call: create droplet
    _set_curl_response '{"droplet":{"id":98765}}'
    # Subsequent calls (IP poll): droplet with IP
    local response_dir="$DO_TEST_TMPDIR/curl_responses"
    mkdir -p "$response_dir"
    echo '{"droplet":{"id":98765,"networks":{"v4":[{"type":"public","ip_address":"203.0.113.42"}],"v6":[{"type":"public","ip_address":"2001:db8::1"}]}}}' > "$response_dir/ip"

    # Override curl stub to return different responses per call count
    cat <<STUB > "$DO_TEST_TMPDIR/stubs/curl"
#!/bin/bash
CALL_FILE="$DO_TEST_TMPDIR/curl_call_count"
count=\$(( \$(cat "\$CALL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "\$count" > "\$CALL_FILE"
if [ "\$count" -eq 1 ]; then
    cat "$response_dir/../curl_response.json"
else
    cat "$response_dir/ip"
fi
STUB
    chmod +x "$DO_TEST_TMPDIR/stubs/curl"

    run cmd_create "my-node" --plan s-2vcpu-4gb --region sfo3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "IPV4:203.0.113.42"
    echo "$output" | grep -q "IPV6:2001:db8::1"
    echo "$output" | grep -q "PROVIDER_ID:98765"
    echo "$output" | grep -q "METADATA:plan=s-2vcpu-4gb"
    echo "$output" | grep -q "METADATA:region=sfo3"
}

@test "cmd_create: fails when DO API returns error" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"message":"Unprocessable Entity"}'
    run cmd_create "my-node"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Unprocessable Entity"
}

@test "cmd_create: fails when droplet id is null" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"droplet":{}}'
    run cmd_create "my-node"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Failed to create"
}

# --- cmd_delete ---

@test "cmd_delete: fails without name" {
    export DO_API_TOKEN="test-fake-token-12345"
    run cmd_delete
    [ "$status" -eq 1 ]
}

@test "cmd_delete: fails when droplet not found" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"droplets":[],"meta":{"total":0}}'
    run cmd_delete "ghost-node"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "not found"
}

@test "cmd_delete: succeeds when droplet exists" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"droplets":[{"id":11111,"name":"my-node"}],"meta":{"total":1}}'
    run cmd_delete "my-node"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "destroyed"
}

@test "cmd_delete: fails without token" {
    unset DO_API_TOKEN
    run cmd_delete "my-node"
    [ "$status" -eq 2 ]
}

# --- cmd_list ---

@test "cmd_list: returns table from API" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"droplets":[{"id":1,"name":"node1","networks":{"v4":[{"type":"public","ip_address":"1.2.3.4"}]},"size_slug":"s-1vcpu-1gb","region":{"slug":"nyc1"},"status":"active"}],"meta":{"total":1}}'
    run cmd_list
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "node1"
}

@test "cmd_list: fails without token" {
    unset DO_API_TOKEN
    run cmd_list
    [ "$status" -eq 2 ]
}

# --- cmd_show ---

@test "cmd_show: fails without name" {
    export DO_API_TOKEN="test-fake-token-12345"
    run cmd_show
    [ "$status" -eq 1 ]
}

@test "cmd_show: fails when droplet not found" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"droplets":[],"meta":{"total":0}}'
    run cmd_show "ghost"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "not found"
}

@test "cmd_show: returns JSON details for existing droplet" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_curl_response '{"droplets":[{"id":22222,"name":"my-node"}],"meta":{"total":1}}'

    # Override curl stub: first call returns list, second returns detail
    cat <<STUB > "$DO_TEST_TMPDIR/stubs/curl"
#!/bin/bash
CALL_FILE="$DO_TEST_TMPDIR/curl_call_count"
count=\$(( \$(cat "\$CALL_FILE" 2>/dev/null || echo 0) + 1 ))
echo "\$count" > "\$CALL_FILE"
if [ "\$count" -eq 1 ]; then
    echo '{"droplets":[{"id":22222,"name":"my-node"}],"meta":{"total":1}}'
else
    echo '{"droplet":{"id":22222,"name":"my-node","status":"active","size":{"slug":"s-2vcpu-4gb"},"region":{"slug":"sfo3"},"networks":{"v4":[{"type":"public","ip_address":"1.2.3.4"}],"v6":[]},"image":{"slug":"ubuntu-24-04-x64"},"created_at":"2025-01-01T00:00:00Z"}}'
fi
STUB
    chmod +x "$DO_TEST_TMPDIR/stubs/curl"

    run cmd_show "my-node"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.id == 22222'
    echo "$output" | jq -e '.name == "my-node"'
}

@test "cmd_show: fails without token" {
    unset DO_API_TOKEN
    run cmd_show "my-node"
    [ "$status" -eq 2 ]
}
