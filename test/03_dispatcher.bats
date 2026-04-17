#!/usr/bin/env bats
# Tests for the DO plugin CLI entry point (dispatcher)

load helpers/common

setup() {
    _setup_do_env
    _setup_do_stubs
}

teardown() {
    _teardown_do_env
}

@test "plugin: no args shows usage" {
    IVPS_PROVIDER_CONFIG="$IVPS_PROVIDER_CONFIG" \
    IVPS_PROVIDER_DIR="$IVPS_PROVIDER_DIR" \
    IVPS_CONFIG_DIR="$IVPS_CONFIG_DIR" \
    run "$PLUGIN_BIN" 2>&1 || true
    echo "$output" | grep -q "Usage"
}

@test "plugin: unknown command shows usage" {
    IVPS_PROVIDER_CONFIG="$IVPS_PROVIDER_CONFIG" \
    IVPS_PROVIDER_DIR="$IVPS_PROVIDER_DIR" \
    IVPS_CONFIG_DIR="$IVPS_CONFIG_DIR" \
    run "$PLUGIN_BIN" nonexistent 2>&1 || true
    echo "$output" | grep -q "Usage"
}

@test "plugin: validate fails without config" {
    IVPS_PROVIDER_CONFIG="$IVPS_PROVIDER_CONFIG" \
    IVPS_PROVIDER_DIR="$IVPS_PROVIDER_DIR" \
    IVPS_CONFIG_DIR="$IVPS_CONFIG_DIR" \
    run "$PLUGIN_BIN" validate 2>&1 || true
    echo "$output" | grep -q "not configured"
}

@test "plugin: list fails without config" {
    IVPS_PROVIDER_CONFIG="$IVPS_PROVIDER_CONFIG" \
    IVPS_PROVIDER_DIR="$IVPS_PROVIDER_DIR" \
    IVPS_CONFIG_DIR="$IVPS_CONFIG_DIR" \
    run "$PLUGIN_BIN" list 2>&1 || true
    echo "$output" | grep -q "not configured"
}

@test "plugin: cloud-init.yaml exists in plugin dir" {
    [ -f "$PROJECT_DIR/cloud-init.yaml" ]
}

@test "plugin: cloud-init.yaml starts with #cloud-config" {
    head -1 "$PROJECT_DIR/cloud-init.yaml" | grep -q "#cloud-config"
}

@test "plugin: cloud-init.yaml references TS_AUTH_KEY" {
    grep -q 'TS_AUTH_KEY' "$PROJECT_DIR/cloud-init.yaml"
}

@test "plugin: cloud-init.yaml references NODE_HOSTNAME" {
    grep -q 'NODE_HOSTNAME' "$PROJECT_DIR/cloud-init.yaml"
}

@test "plugin: cloud-init.yaml references IS_GATEWAY" {
    grep -q 'IS_GATEWAY' "$PROJECT_DIR/cloud-init.yaml"
}
