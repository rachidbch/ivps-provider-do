# CLAUDE.md — ivps-provider-do conventions

## Project

DigitalOcean provider plugin for [ivps](https://github.com/rachidbch/ivps). Single-file Bash (`plugin`) implementing the IVPS plugin interface (keys/validate/create/delete/list/show). Bundles `cloud-init.yaml` for node bootstrapping.

Credentials are received as env vars (auto-exported by ivps from `config.env`). This plugin never reads or writes credential files.

Cloud-init templating and cleanup-on-failure are handled by ivps core — the plugin does **not** need `envsubst`, SSH key discovery, or cleanup traps.

## Dependencies

- **doctl** — Official DigitalOcean CLI. Handles auth, retry, and polling. Install: https://docs.digitalocean.com/reference/doctl/how-to/install/
- **jq** — JSON parsing (required by ivps core, available system-wide)

Note: `envsubst` is no longer a plugin dependency — ivps core handles cloud-init templating and includes `envsubst` in its own `check_deps`. `doctl` is a provider-specific dependency checked by `require_doctl`.

## Exit Codes

```
0 = success
1 = general error (bad args, API errors)
2 = auth/credential error (missing/invalid token)
3 = resource not found
4 = dependency missing (doctl)
```

## Plugin Contract

Required subcommands:

```
plugin keys                     # Output DO_API_TOKEN:DigitalOcean API Token
plugin validate                 # Check DO_API_TOKEN via doctl; exit 0=ok, 2=bad/missing
plugin create <name> [options]  # Provision a droplet (doctl --wait, no IP polling)
plugin delete <name>            # Destroy a droplet (exit 3 if not found)
plugin list                     # List droplets (doctl -o json array)
plugin show <name>              # Show droplet details (doctl -o json single object)
```

Env vars consumed: `DO_API_TOKEN` (required), `IVPS_CONFIG_DIR`, `IVPS_PROVIDER_DIR`.

### `plugin create` arguments

```
plugin create <name> [--plan <slug>] [--region <slug>] [--image <slug>] [--cloud-init <path>]
```

- `--cloud-init <path>` — Pre-templated cloud-init file rendered by ivps core. Passed directly to `doctl --user-data-file`. May be absent if the plugin has no `cloud-init.yaml`.

### doctl JSON output structure

- `doctl compute droplet create -o json` → JSON array `[{}]` (supports multi-create)
- `doctl compute droplet get <name> -o json` → single object `{}`
- `doctl compute droplet list -o json` → JSON array `[{},...]`
- `doctl account get -o json` → single object `{}`
- Key fields: `.id`, `.name`, `.status`, `.networks.v4[]`, `.networks.v6[]`, `.size.slug`, `.region.slug`, `.image.slug`

## Helper Functions

- **`require_token`** — Exits with 2 if `DO_API_TOKEN` is unset/empty
- **`require_doctl`** — Exits with 4 if `doctl` not in PATH

## What ivps Core Handles

The plugin does NOT need to implement:

- **Cloud-init templating** — ivps runs `envsubst` on the plugin's `cloud-init.yaml` and passes the result via `--cloud-init <path>`
- **SSH key discovery** — ivps finds the user's public key and injects `${SSH_PUBLIC_KEY}` into the template
- **Cleanup on failure** — If post-create steps fail (SSH wait, cloud-init wait, etc.), ivps calls `plugin delete <name>`

## Test-Driven Development (TDD)

**Always write tests first.** Uses [bats-core](https://github.com/bats-core/bats-core) (v1.13+).

### Running tests

```bash
bats test/                # all tests
bats test/01_helpers.bats # single file
bats test/ -f "require"   # filter by name
```

### Test structure

```
test/
  helpers/
    common.bash         # _setup_do_env, _setup_do_stubs,
                        # _set_doctl_response, source_plugin_functions,
                        # _setup_integration_env, _create_boot_sequence_stubs,
                        # _advance_boot_state, _create_ssh_key_stub,
                        # _cleanup_integration_env
  01_helpers.bats       # require_token, require_doctl, cmd_keys
  02_commands.bats      # validate, create (--cloud-init), delete, list, show
  03_dispatcher.bats    # CLI entry point, usage text, cloud-init.yaml validation
  04_integration.bats   # full node lifecycle through ivps (create→SSH→cloud-init→Incus→destroy)
```

### Writing a test

1. `load helpers/common` at top
2. `_setup_do_env` / `_teardown_do_env` in setup/teardown
3. `_setup_do_stubs` provides a doctl stub that reads `_set_doctl_response`
4. For multi-call doctl scenarios, override the stub with call-count logic
5. `source_plugin_functions` loads all functions without the dispatcher
6. Use `export DO_API_TOKEN="..."` to set credentials for tests
7. Use `unset DO_API_TOKEN` to test missing-credential paths

### Key patterns

- **doctl stubbing**: `_set_doctl_response '<json>'` controls what doctl "returns"
- **No real network**: tests never call `api.digitalocean.com` or real `doctl`
- **Multi-call doctl**: write a call-counting stub that returns different responses per invocation (used in delete flow)
- **Credential isolation**: each test sets/unsets `DO_API_TOKEN` directly via export/unset

### Integration test patterns

- **Full lifecycle**: `_setup_integration_env` creates a complete ivps environment with the DO plugin installed, stubs for doctl/ssh/incus/nc/sleep, and a state machine simulating node boot
- **doctl stub**: routes subcommands: `droplet create` (returns IP immediately via --wait), `droplet get`, `droplet delete`, `droplet list`, `account get`
- **Boot state machine**: stubs auto-advance through states: `created` → `ip_assigned` → `ssh_ready` → `cloud_init_running` → `cloud_init_done` → `incus_api_ready`
- **Manual state control**: `_advance_boot_state [state]` to jump to a specific state (e.g., `"destroyed"` for delete tests)
- **Sleep logging**: stub records sleep durations to `$DO_TEST_TMPDIR/sleep_log` — should be empty since `doctl --wait` eliminates IP polling
- **Invocation logging**: stubs log all calls to `$DO_TEST_TMPDIR/{ssh,incus}_log` for verification
