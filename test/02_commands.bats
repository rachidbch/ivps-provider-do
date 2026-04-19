#!/usr/bin/env bats
# Tests for DO plugin subcommands (validate, create, delete, list, show)

load helpers/common

setup() {
    _setup_do_env
    _setup_do_stubs
    source_plugin_functions
    # Export exit code constants for test assertions
    export EXIT_OK=0
    export EXIT_ERR=1
    export EXIT_AUTH=2
    export EXIT_NOTFOUND=3
    export EXIT_DEP=4
}

teardown() {
    _teardown_do_env
}

# --- cmd_validate ---

@test "cmd_validate: succeeds with valid account response" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_doctl_response '{"email":"test@example.com","droplet_limit":25,"status":"active"}'
    run cmd_validate
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Authenticated"
}

@test "cmd_validate: fails with bad token" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_doctl_response '{"id":"Forbidden","message":"You are not authorized"}'
    run cmd_validate
    [ "$status" -eq "$EXIT_AUTH" ]
    echo "$output" | grep -q "Failed to authenticate"
}

@test "cmd_validate: fails without token" {
    unset DO_API_TOKEN
    run cmd_validate
    [ "$status" -eq "$EXIT_AUTH" ]
}

# --- cmd_create ---

@test "cmd_create: fails without name" {
    export DO_API_TOKEN="test-fake-token-12345"
    run cmd_create
    [ "$status" -eq "$EXIT_ERR" ]
    echo "$output" | grep -q "Usage"
}

@test "cmd_create: fails without token" {
    unset DO_API_TOKEN
    run cmd_create "my-node"
    [ "$status" -eq "$EXIT_AUTH" ]
}

@test "cmd_create: returns IPV4/PROVIDER_ID on success via doctl --wait" {
    export DO_API_TOKEN="test-fake-token-12345"
    # doctl compute droplet create -o json returns a JSON array
    _set_doctl_response '[{"id":98765,"name":"my-node","status":"active","networks":{"v4":[{"type":"public","ip_address":"203.0.113.42"}],"v6":[{"type":"public","ip_address":"2001:db8::1"}]},"size":{"slug":"s-2vcpu-4gb"},"region":{"slug":"sfo3"}}]'

    run cmd_create "my-node" --plan s-2vcpu-4gb --region sfo3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "IPV4:203.0.113.42"
    echo "$output" | grep -q "IPV6:2001:db8::1"
    echo "$output" | grep -q "PROVIDER_ID:98765"
    echo "$output" | grep -q "METADATA:plan=s-2vcpu-4gb"
    echo "$output" | grep -q "METADATA:region=sfo3"
}

@test "cmd_create: passes --cloud-init file to doctl as user-data-file" {
    export DO_API_TOKEN="test-fake-token-12345"
    local cloud_init_file="$DO_TEST_TMPDIR/test-cloud-init.yaml"
    echo "#cloud-config" > "$cloud_init_file"

    # doctl stub that logs arguments
    local call_log="$DO_TEST_TMPDIR/create_calls"
    : > "$call_log"
    cat <<STUB > "$DO_TEST_TMPDIR/stubs/doctl"
#!/bin/bash
echo "\$*" >> "$call_log"
if echo "\$*" | grep -q "droplet create"; then
    echo '[{"id":55555,"name":"ci-test","status":"active","networks":{"v4":[{"type":"public","ip_address":"10.0.0.5"}],"v6":[]},"size":{"slug":"s-2vcpu-4gb"},"region":{"slug":"nyc1"}}]'
fi
STUB
    chmod +x "$DO_TEST_TMPDIR/stubs/doctl"

    run cmd_create "ci-test" --cloud-init "$cloud_init_file"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "IPV4:10.0.0.5"

    # Verify --user-data-file was passed to doctl
    grep -q "\-\-user-data-file" "$call_log"
    grep -q "$cloud_init_file" "$call_log"
}

@test "cmd_create: fails when doctl returns error" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_doctl_response 'Error: POST https://api.digitalocean.com/v2/droplets: 422 Unprocessable Entity'
    run cmd_create "my-node"
    [ "$status" -eq "$EXIT_ERR" ]
    echo "$output" | grep -q "Error"
}

@test "cmd_create: fails when droplet id is null in response" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_doctl_response '[{"name":"my-node"}]'
    run cmd_create "my-node"
    [ "$status" -eq "$EXIT_ERR" ]
    echo "$output" | grep -q "\[ERROR\]"
}

# --- cmd_delete ---

@test "cmd_delete: fails without name" {
    export DO_API_TOKEN="test-fake-token-12345"
    run cmd_delete
    [ "$status" -eq "$EXIT_ERR" ]
}

@test "cmd_delete: fails when droplet not found" {
    export DO_API_TOKEN="test-fake-token-12345"
    # doctl get returns error for non-existent droplet
    _set_doctl_response 'Error: unable to find droplet'
    run cmd_delete "ghost-node"
    [ "$status" -eq "$EXIT_NOTFOUND" ]
    echo "$output" | grep -q "not found"
}

@test "cmd_delete: succeeds when droplet exists" {
    export DO_API_TOKEN="test-fake-token-12345"
    # First call: doctl compute droplet get (lookup) returns droplet info
    # Second call: doctl compute droplet delete (destroy) returns nothing
    local call_count_file="$DO_TEST_TMPDIR/delete_call_count"
    echo "0" > "$call_count_file"
    cat <<STUB > "$DO_TEST_TMPDIR/stubs/doctl"
#!/bin/bash
count=\$(( \$(cat "$call_count_file") + 1 ))
echo "\$count" > "$call_count_file"
if [ "\$count" -eq 1 ]; then
    # droplet get response
    echo '{"id":11111,"name":"my-node"}'
fi
# delete returns nothing (success)
STUB
    chmod +x "$DO_TEST_TMPDIR/stubs/doctl"

    run cmd_delete "my-node"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "destroyed"
}

@test "cmd_delete: fails without token" {
    unset DO_API_TOKEN
    run cmd_delete "my-node"
    [ "$status" -eq "$EXIT_AUTH" ]
}

# --- cmd_list ---

@test "cmd_list: returns table from doctl JSON array" {
    export DO_API_TOKEN="test-fake-token-12345"
    _set_doctl_response '[{"id":1,"name":"node1","networks":{"v4":[{"type":"public","ip_address":"1.2.3.4"}]},"size":{"slug":"s-1vcpu-1gb"},"region":{"slug":"nyc1"},"status":"active"}]'
    run cmd_list
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "node1"
}

@test "cmd_list: fails without token" {
    unset DO_API_TOKEN
    run cmd_list
    [ "$status" -eq "$EXIT_AUTH" ]
}

# --- cmd_show ---

@test "cmd_show: fails without name" {
    export DO_API_TOKEN="test-fake-token-12345"
    run cmd_show
    [ "$status" -eq "$EXIT_ERR" ]
}

@test "cmd_show: fails when droplet not found" {
    export DO_API_TOKEN="test-fake-token-12345"
    # doctl returns error message for non-existent droplet
    _set_doctl_response 'Error: unable to find droplet'
    run cmd_show "ghost"
    [ "$status" -eq "$EXIT_NOTFOUND" ]
    echo "$output" | grep -q "not found"
}

@test "cmd_show: returns JSON details for existing droplet" {
    export DO_API_TOKEN="test-fake-token-12345"
    # doctl compute droplet get returns a single object (not wrapped)
    _set_doctl_response '{"id":22222,"name":"my-node","status":"active","size":{"slug":"s-2vcpu-4gb"},"region":{"slug":"sfo3"},"networks":{"v4":[{"type":"public","ip_address":"1.2.3.4"}],"v6":[]},"image":{"slug":"ubuntu-24-04-x64"},"created_at":"2025-01-01T00:00:00Z"}'
    run cmd_show "my-node"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.id == 22222'
    echo "$output" | jq -e '.name == "my-node"'
}

@test "cmd_show: fails without token" {
    unset DO_API_TOKEN
    run cmd_show "my-node"
    [ "$status" -eq "$EXIT_AUTH" ]
}
