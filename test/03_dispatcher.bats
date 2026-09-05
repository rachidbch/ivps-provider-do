#!/usr/bin/env bats
# Tests for plugin interface validation and cloud-init.yaml

load helpers/common

setup() {
    _setup_do_env
    _setup_do_stubs
}

teardown() {
    _teardown_do_env
}

# --- Interface validation ---

@test "plugin: cmd_keys is a function" {
    source_plugin_functions
    [ "$(type -t cmd_keys)" = "function" ]
}

@test "plugin: cmd_validate is a function" {
    source_plugin_functions
    [ "$(type -t cmd_validate)" = "function" ]
}

@test "plugin: cmd_create is a function" {
    source_plugin_functions
    [ "$(type -t cmd_create)" = "function" ]
}

@test "plugin: cmd_delete is a function" {
    source_plugin_functions
    [ "$(type -t cmd_delete)" = "function" ]
}

@test "plugin: cmd_list is a function" {
    source_plugin_functions
    [ "$(type -t cmd_list)" = "function" ]
}

@test "plugin: cmd_show is a function" {
    source_plugin_functions
    [ "$(type -t cmd_show)" = "function" ]
}

@test "plugin: keys outputs credential key names" {
    source_plugin_functions
    run cmd_keys
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "DO_API_TOKEN:DigitalOcean API Token"
}

@test "plugin: validate fails without token" {
    source_plugin_functions
    run cmd_validate 2>&1 || true
    echo "$output" | grep -q "not set"
}

@test "plugin: list fails without token" {
    source_plugin_functions
    run cmd_list 2>&1 || true
    echo "$output" | grep -q "not set"
}

# --- cloud-init.yaml ---

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
