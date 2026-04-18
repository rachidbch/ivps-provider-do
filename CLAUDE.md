# CLAUDE.md — ivps-provider-do conventions

## Project

DigitalOcean provider plugin for [ivps](https://github.com/rachidbch/ivps). Single-file Bash (`plugin`) implementing the IVPS plugin interface (keys/validate/create/delete/list/show). Bundles `cloud-init.yaml` for node bootstrapping.

Credentials are received as env vars (auto-exported by ivps from `config.env`). This plugin never reads or writes credential files.

## Plugin Contract

Required subcommands:

```
plugin keys                     # Output DO_API_TOKEN:DigitalOcean API Token
plugin validate                 # Check DO_API_TOKEN via DO API; exit 0=ok, 1=bad, 2=missing
plugin create <name> [options]  # Provision a droplet
plugin delete <name>            # Destroy a droplet
plugin list                     # List droplets
plugin show <name>              # Show droplet details
```

Env vars consumed: `DO_API_TOKEN` (required), `IVPS_CONFIG_DIR`, `IVPS_PROVIDER_DIR`.

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
                        # _set_curl_response, source_plugin_functions
  01_helpers.bats       # require_token, do_api, cmd_keys
  02_commands.bats      # validate, create, delete, list, show (with canned API responses)
  03_dispatcher.bats    # CLI entry point, usage text, cloud-init.yaml validation
```

### Writing a test

1. `load helpers/common` at top
2. `_setup_do_env` / `_teardown_do_env` in setup/teardown
3. `_setup_do_stubs` provides a curl stub that reads `_set_curl_response`
4. For multi-call curl scenarios (create→poll IP), override the stub with call-count logic
5. `source_plugin_functions` loads all functions without the dispatcher
6. Use `export DO_API_TOKEN="..."` to set credentials for tests
7. Use `unset DO_API_TOKEN` to test missing-credential paths

### Key patterns

- **Curl stubbing**: `_set_curl_response '<json>'` controls what the DO API "returns"
- **No real network**: tests never call `api.digitalocean.com`
- **Multi-call curl**: write a call-counting stub that returns different responses per invocation (used in create flow)
- **Credential isolation**: each test sets/unsets `DO_API_TOKEN` directly via export/unset
