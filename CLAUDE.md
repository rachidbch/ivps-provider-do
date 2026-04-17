# CLAUDE.md — ivps-provider-do conventions

## Project

DigitalOcean provider plugin for [ivps](https://github.com/rachidbch/ivps). Single-file Bash (`plugin`) implementing the IVPS plugin interface (setup/validate/create/delete/list/show). Bundles `cloud-init.yaml` for node bootstrapping.

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
    common.bash         # _setup_do_env, _write_provider_config, _setup_do_stubs,
                        # _set_curl_response, source_plugin_functions
  01_helpers.bats       # load_provider_config, require_token, do_api
  02_commands.bats      # validate, create, delete, list, show (with canned API responses)
  03_dispatcher.bats    # CLI entry point, usage text, cloud-init.yaml validation
```

### Writing a test

1. `load helpers/common` at top
2. `_setup_do_env` / `_teardown_do_env` in setup/teardown
3. `_setup_do_stubs` provides a curl stub that reads `_set_curl_response`
4. For multi-call curl scenarios (create→poll IP), override the stub with call-count logic
5. `source_plugin_functions` loads all functions without the dispatcher

### Key patterns

- **Curl stubbing**: `_set_curl_response '<json>'` controls what the DO API "returns"
- **No real network**: tests never call `api.digitalocean.com`
- **Multi-call curl**: write a call-counting stub that returns different responses per invocation (used in create flow)
- **Config isolation**: each test gets a fresh temp provider config via `_write_provider_config`
