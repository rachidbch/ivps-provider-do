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
    export IVPS_PROVIDER_CONFIG="$IVPS_CONFIG_DIR/providers/digitalocean.env"
    mkdir -p "$IVPS_CONFIG_DIR/providers"
}

_teardown_do_env() {
    rm -rf "$DO_TEST_TMPDIR"
}

# Write a valid provider config
_write_provider_config() {
    local token="${1-test-fake-token-12345}"
    cat <<EOF > "$IVPS_PROVIDER_CONFIG"
# DigitalOcean Provider Configuration
DO_API_TOKEN="$token"
EOF
    chmod 600 "$IVPS_PROVIDER_CONFIG"
}

# Stub curl to return canned DO API responses
_setup_do_stubs() {
    local stub_dir="$DO_TEST_TMPDIR/stubs"
    mkdir -p "$stub_dir"

    # Real jq passthrough
    if command -v jq &>/dev/null; then
        ln -sf "$(command -v jq)" "$stub_dir/jq"
    fi

    # curl stub — reads response from DO_CURL_RESPONSE_FILE or returns empty
    cat <<'STUB' > "$stub_dir/curl"
#!/bin/bash
# Parse the endpoint from args for routing
endpoint=""
method=""
for arg in "$@"; do
    case "$arg" in
        https://api.digitalocean.com/v2*) endpoint="$arg" ;;
        -X) next_is_method=1 ;;
        *)
            [ "${next_is_method:-0}" = "1" ] && { method="$arg"; next_is_method=0; }
            ;;
    esac
done

# Check for canned responses
if [ -f "${DO_CURL_RESPONSE_FILE:-/dev/null}" ]; then
    cat "$DO_CURL_RESPONSE_FILE"
else
    echo '{"droplets":[],"meta":{"total":0}}'
fi
STUB
    chmod +x "$stub_dir/curl"

    export PATH="$stub_dir:$PATH"
}

# Write a canned curl response to a temp file
_set_curl_response() {
    export DO_CURL_RESPONSE_FILE="$DO_TEST_TMPDIR/curl_response.json"
    echo "$1" > "$DO_CURL_RESPONSE_FILE"
}

# Source plugin functions without the dispatcher
source_plugin_functions() {
    eval "$(sed '/^# --- DISPATCHER ---$/,$d' "$PLUGIN_BIN" | grep -v '^set -e')"
}
