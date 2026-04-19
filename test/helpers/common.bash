#!/usr/bin/env bash
# Shared test helpers for ivps-provider-do bats tests

TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
PROJECT_DIR="$(cd "$TEST_DIR/.." && pwd)"
PLUGIN_BIN="$PROJECT_DIR/plugin"

# Temp environment — each test gets a fresh one
_setup_do_env() {
    export DO_TEST_TMPDIR="$(mktemp -d)"
    export XDG_CONFIG_HOME="$DO_TEST_TMPDIR/config"
    export IVPS_CONFIG_DIR="$XDG_CONFIG_HOME/ivps"
    export IVPS_PROVIDER_DIR="$PROJECT_DIR"
    mkdir -p "$IVPS_CONFIG_DIR"
}

_teardown_do_env() {
    rm -rf "$DO_TEST_TMPDIR"
}

# Stub doctl to return canned DO API responses
_setup_do_stubs() {
    local stub_dir="$DO_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"

    # Real jq passthrough
    if command -v jq &>/dev/null; then
        ln -sf "$(command -v jq)" "$stub_dir/jq"
    fi

    # doctl stub — reads response from DO_CTL_RESPONSE_FILE or returns empty
    cat <<'STUB' > "$stub_dir/doctl"
#!/bin/bash
# Route doctl subcommands
subcmd="$1"
shift

# Check for canned responses
if [ -f "${DO_CTL_RESPONSE_FILE:-/dev/null}" ]; then
    cat "$DO_CTL_RESPONSE_FILE"
else
    echo '[]'
fi
STUB
    chmod +x "$stub_dir/doctl"

    export PATH="$stub_dir:$PATH"
}

# Write a canned doctl response to a temp file
_set_doctl_response() {
    export DO_CTL_RESPONSE_FILE="$DO_TEST_TMPDIR/doctl_response.json"
    echo "$1" > "$DO_CTL_RESPONSE_FILE"
}

# Backward-compatible alias
_set_curl_response() {
    _set_doctl_response "$1"
}

# Source plugin functions without the dispatcher
source_plugin_functions() {
    eval "$(sed '/^# --- DISPATCHER ---$/,$d' "$PLUGIN_BIN" | grep -v '^set -e')"
}

# --- Integration test helpers ---

# Paths for the ivps main project (used by integration tests)
IVPS_PROJECT_DIR="$(cd "$PROJECT_DIR/../ivps" && pwd)"
IVPS_BIN="$IVPS_PROJECT_DIR/ivps"

# Full integration environment: sets up ivps config dir, installs DO plugin,
# creates all necessary stubs for the node lifecycle.
_setup_integration_env() {
    export DO_TEST_TMPDIR="$(mktemp -d)"
    export XDG_CONFIG_HOME="$DO_TEST_TMPDIR/config"
    export IVPS_CONFIG_DIR="$XDG_CONFIG_HOME/ivps"
    export CONFIG_DIR="$IVPS_CONFIG_DIR"
    export CONFIG_FILE="$IVPS_CONFIG_DIR/config.env"
    export PLUGINS_DIR="$IVPS_CONFIG_DIR/plugins"
    export NODES_DIR="$IVPS_CONFIG_DIR/nodes"
    export PROVIDERS_DIR="$IVPS_CONFIG_DIR/providers"

    mkdir -p "$IVPS_CONFIG_DIR" "$PLUGINS_DIR" "$NODES_DIR" "$PROVIDERS_DIR"

    # Write config.env with test values
    cat <<EOF > "$CONFIG_FILE"
# IVPS Configuration
TS_AUTH_KEY="tskey-auth-test-integration"
TS_DOMAIN="test.ts.net"
IVPS_GATEWAY=""

# Provider: digitalocean
DO_API_TOKEN="dop_v1_test_integration_token"
EOF

    # Install DO plugin into ivps plugins dir
    cp -r "$PROJECT_DIR" "$PLUGINS_DIR/digitalocean"
    chmod +x "$PLUGINS_DIR/digitalocean/plugin"

    # Create fake SSH key
    _create_ssh_key_stub

    # Create all stubs for boot sequence simulation
    _create_boot_sequence_stubs
}

# Create a fake SSH key for tests
_create_ssh_key_stub() {
    local ssh_dir="$DO_TEST_TMPDIR/ssh"
    mkdir -p "$ssh_dir"
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeTestKeyForIVPSIntegration test@ivps" > "$ssh_dir/id_ed25519.pub"
    echo "-----BEGIN OPENSSH PRIVATE KEY-----" > "$ssh_dir/id_ed25519"
    echo "fake-test-key-content" >> "$ssh_dir/id_ed25519"
    echo "-----END OPENSSH PRIVATE KEY-----" >> "$ssh_dir/id_ed25519"
    chmod 600 "$ssh_dir/id_ed25519"
    chmod 644 "$ssh_dir/id_ed25519.pub"
    # Override HOME so SSH looks here
    export HOME="$DO_TEST_TMPDIR/home"
    mkdir -p "$HOME/.ssh"
    ln -sf "$ssh_dir/id_ed25519" "$HOME/.ssh/id_ed25519"
    ln -sf "$ssh_dir/id_ed25519.pub" "$HOME/.ssh/id_ed25519.pub"
}

# Create stateful stubs that simulate a node booting progressively.
# Uses a state file ($DO_TEST_TMPDIR/node_state) to track boot progress.
#
# States: created → ip_assigned → ssh_ready → cloud_init_running →
#         cloud_init_done → incus_api_ready
#
# _advance_boot_state [<new_state>] advances to the next state or to the
# specified one.
_create_boot_sequence_stubs() {
    local stub_dir="$DO_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"

    # Initialize state
    echo "created" > "$DO_TEST_TMPDIR/node_state"

    # Real jq passthrough
    if command -v jq &>/dev/null; then
        ln -sf "$(command -v jq)" "$stub_dir/jq"
    fi

    # Real envsubst passthrough
    if command -v envsubst &>/dev/null; then
        ln -sf "$(command -v envsubst)" "$stub_dir/envsubst"
    fi

    # --- doctl stub ---
    # Routes doctl subcommands:
    #   compute droplet create (with --wait) → returns JSON array with IP immediately
    #   compute droplet get <name>            → returns single object
    #   compute droplet delete <name>         → returns nothing (success)
    #   compute droplet list                  → returns JSON array
    #   account get                           → returns account JSON
    cat <<'DOCTL_STUB' > "$stub_dir/doctl"
#!/bin/bash
STATE_FILE="__DO_TEST_TMPDIR__/node_state"
DROPLET_ID="12345678"
DROPLET_NAME="__DO_NODE_NAME__"
STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "created")

# Route based on subcommands
if echo "$*" | grep -q "droplet create"; then
    # compute droplet create --wait → returns array with IP immediately
    # Auto-advance to ip_assigned since --wait blocks until active
    echo "ip_assigned" > "$STATE_FILE"
    echo "[{\"id\":$DROPLET_ID,\"name\":\"$DROPLET_NAME\",\"status\":\"active\",\"networks\":{\"v4\":[{\"type\":\"public\",\"ip_address\":\"203.0.113.42\"}],\"v6\":[{\"type\":\"public\",\"ip_address\":\"2001:db8::1\"}]},\"size\":{\"slug\":\"s-2vcpu-4gb\"},\"region\":{\"slug\":\"nyc1\"},\"image\":{\"slug\":\"ubuntu-24-04-x64\"}}]"
elif echo "$*" | grep -q "droplet delete"; then
    # compute droplet delete → success (no output)
    exit 0
elif echo "$*" | grep -q "droplet get"; then
    # compute droplet get <name> → single object or error
    if [ "$STATE" = "destroyed" ]; then
        echo "Error: unable to find droplet"
        exit 1
    else
        echo "{\"id\":$DROPLET_ID,\"name\":\"$DROPLET_NAME\",\"status\":\"active\",\"networks\":{\"v4\":[{\"type\":\"public\",\"ip_address\":\"203.0.113.42\"}],\"v6\":[{\"type\":\"public\",\"ip_address\":\"2001:db8::1\"}]},\"size\":{\"slug\":\"s-2vcpu-4gb\"},\"region\":{\"slug\":\"nyc1\"},\"image\":{\"slug\":\"ubuntu-24-04-x64\"},\"created_at\":\"2025-01-01T00:00:00Z\"}"
    fi
elif echo "$*" | grep -q "droplet list"; then
    # compute droplet list → JSON array
    if [ "$STATE" != "destroyed" ]; then
        echo "[{\"id\":$DROPLET_ID,\"name\":\"$DROPLET_NAME\",\"status\":\"active\",\"networks\":{\"v4\":[{\"type\":\"public\",\"ip_address\":\"203.0.113.42\"}]},\"size\":{\"slug\":\"s-2vcpu-4gb\"},\"region\":{\"slug\":\"nyc1\"},\"status\":\"active\"}]"
    else
        echo "[]"
    fi
elif echo "$*" | grep -q "account get"; then
    echo "{\"email\":\"test@example.com\",\"droplet_limit\":25,\"status\":\"active\"}"
else
    echo "[]"
fi
DOCTL_STUB
    # Replace placeholders with actual values
    sed -i "s|__DO_TEST_TMPDIR__|$DO_TEST_TMPDIR|g" "$stub_dir/doctl"
    sed -i "s|__DO_NODE_NAME__|test-node|g" "$stub_dir/doctl"
    chmod +x "$stub_dir/doctl"

    # --- sleep stub (instant for tests) ---
    cat <<'SLEEP_STUB' > "$stub_dir/sleep"
#!/bin/bash
# Record sleep duration for verification
echo "$1" >> "__DO_TEST_TMPDIR__/sleep_log"
SLEEP_STUB
    sed -i "s|__DO_TEST_TMPDIR__|$DO_TEST_TMPDIR|g" "$stub_dir/sleep"
    chmod +x "$stub_dir/sleep"

    # --- ssh stub ---
    # Routes based on state and the command being executed:
    #   cloud-init status → returns status based on state, auto-advances cloud_init_running → cloud_init_done
    #   incus config trust add → returns a fake token
    #   other commands → returns generic success output
    cat <<'SSH_STUB' > "$stub_dir/ssh"
#!/bin/bash
STATE_FILE="__DO_TEST_TMPDIR__/node_state"
STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "created")

# Record SSH invocations for verification
echo "$*" >> "__DO_TEST_TMPDIR__/ssh_log"

# Parse the remote command (last arg after -- or after user@host)
remote_cmd=""
for arg in "$@"; do
    remote_cmd="$arg"
done

if echo "$remote_cmd" | grep -q "cloud-init status"; then
    if [ "$STATE" = "cloud_init_done" ] || [ "$STATE" = "incus_api_ready" ]; then
        echo "status: done"
    elif [ "$STATE" = "cloud_init_running" ]; then
        # Auto-advance: next cloud-init check will see "done"
        echo "cloud_init_done" > "$STATE_FILE"
        echo "status: running"
    elif [ "$STATE" = "ssh_ready" ] || [ "$STATE" = "ip_assigned" ]; then
        # Auto-advance into cloud-init lifecycle
        echo "cloud_init_running" > "$STATE_FILE"
        echo "status: running"
    else
        echo "status: not started"
    fi
elif echo "$remote_cmd" | grep -q "incus config trust add"; then
    echo "test-fake-trust-token-abc123"
elif echo "$remote_cmd" | grep -q "uname"; then
    echo "Linux test-node 6.1.0-generic x86_64"
elif echo "$remote_cmd" | grep -q "uptime"; then
    echo " 10:30:00 up 5 min,  1 user,  load average: 0.1, 0.2, 0.1"
elif echo "$remote_cmd" | grep -q "incus version"; then
    echo "Incus 6.0.0"
elif echo "$remote_cmd" | grep -q "apt-get install"; then
    echo "Reading package lists... Done"
    echo "Setting up fake-package (1.0) ..."
elif echo "$remote_cmd" | grep -q "dpkg -l"; then
    echo "ii  fake-package   1.0   amd64   A fake test package"
else
    # Generic SSH command success
    echo "SSH_OK: $remote_cmd"
fi
SSH_STUB
    sed -i "s|__DO_TEST_TMPDIR__|$DO_TEST_TMPDIR|g" "$stub_dir/ssh"
    chmod +x "$stub_dir/ssh"

    # --- incus stub ---
    cat <<'INCUS_STUB' > "$stub_dir/incus"
#!/bin/bash
STATE_FILE="__DO_TEST_TMPDIR__/node_state"
STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "created")

# Record incus invocations for verification
echo "$*" >> "__DO_TEST_TMPDIR__/incus_log"

if echo "$*" | grep -q "remote add"; then
    echo "REMOTE_ADDED"
elif echo "$*" | grep -q "remote remove"; then
    echo "REMOTE_REMOVED"
elif echo "$*" | grep -q "remote list"; then
    if [ "$STATE" != "destroyed" ]; then
        echo '{"test-node":{"Addr":"https://203.0.113.42:8443"}}' | jq -c '.'
    else
        echo '{}'
    fi
elif echo "$*" | grep -q "list"; then
    if [ "$STATE" != "destroyed" ]; then
        echo '[{"name":"test-container","status":"Running","state":{"network":{"eth0":{"addresses":[{"family":"inet","address":"10.0.0.1"}]}}}}]'
    else
        echo '[]'
    fi
elif echo "$*" | grep -q "info"; then
    echo "INCUS_INFO_OK"
else
    echo "INCUS_STUB: $*"
fi
INCUS_STUB
    sed -i "s|__DO_TEST_TMPDIR__|$DO_TEST_TMPDIR|g" "$stub_dir/incus"
    chmod +x "$stub_dir/incus"

    # --- nc stub ---
    # Port is reachable when state >= ssh_ready for port 22,
    # and when state >= incus_api_ready for port 8443.
    # Auto-advances: ip_assigned → ssh_ready on port 22 check,
    # cloud_init_done → incus_api_ready on port 8443 check.
    cat <<'NC_STUB' > "$stub_dir/nc"
#!/bin/bash
STATE_FILE="__DO_TEST_TMPDIR__/node_state"
STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "created")

# Parse port from args
port=""
for arg in "$@"; do
    if echo "$arg" | grep -qE '^[0-9]+$'; then
        port="$arg"
    fi
done

if [ "$port" = "22" ]; then
    # Auto-advance: ip_assigned → ssh_ready
    if [ "$STATE" = "ip_assigned" ]; then
        echo "ssh_ready" > "$STATE_FILE"
    fi
    if [ "$STATE" = "ssh_ready" ] || [ "$STATE" = "cloud_init_running" ] || \
       [ "$STATE" = "cloud_init_done" ] || [ "$STATE" = "incus_api_ready" ] || \
       [ "$STATE" = "ip_assigned" ]; then
        exit 0
    fi
    exit 1
elif [ "$port" = "8443" ]; then
    # Auto-advance: cloud_init_done → incus_api_ready
    if [ "$STATE" = "cloud_init_done" ]; then
        echo "incus_api_ready" > "$STATE_FILE"
    fi
    if [ "$STATE" = "incus_api_ready" ] || [ "$STATE" = "cloud_init_done" ]; then
        exit 0
    fi
    exit 1
else
    exit 0
fi
NC_STUB
    sed -i "s|__DO_TEST_TMPDIR__|$DO_TEST_TMPDIR|g" "$stub_dir/nc"
    chmod +x "$stub_dir/nc"

    # Clear logs
    : > "$DO_TEST_TMPDIR/sleep_log"
    : > "$DO_TEST_TMPDIR/ssh_log"
    : > "$DO_TEST_TMPDIR/incus_log"

    export PATH="$stub_dir:$PATH"
}

# Advance the simulated node boot state.
# Usage: _advance_boot_state [new_state]
# States: created → ip_assigned → ssh_ready → cloud_init_running →
#         cloud_init_done → incus_api_ready
_advance_boot_state() {
    local new_state="${1:-}"
    local state_file="$DO_TEST_TMPDIR/node_state"

    if [ -n "$new_state" ]; then
        echo "$new_state" > "$state_file"
        return
    fi

    local current
    current=$(cat "$state_file" 2>/dev/null || echo "created")
    case "$current" in
        created)           echo "ip_assigned" > "$state_file" ;;
        ip_assigned)       echo "ssh_ready" > "$state_file" ;;
        ssh_ready)         echo "cloud_init_running" > "$state_file" ;;
        cloud_init_running) echo "cloud_init_done" > "$state_file" ;;
        cloud_init_done)   echo "incus_api_ready" > "$state_file" ;;
        incus_api_ready)   ;; # already at end
    esac
}

# Clean up integration environment
_cleanup_integration_env() {
    rm -rf "$DO_TEST_TMPDIR"
}
