---
name: settings
description: |
  Runtime configuration management for the charly CLI.
  MUST be invoked before any work involving: charly settings commands, runtime configuration, engine selection, bind address, storage paths, or secret backend configuration.
---

# charly settings -- Runtime Configuration

## Overview

Manage charly's runtime configuration stored in `~/.config/charly/config.yml`. Controls engine selection, networking, storage paths, secret backend, and agent forwarding.

`charly settings` is a **compiled-in COMMAND-class plugin** (`candy/plugin-settings`, `command:settings`) that OWNS the command — the get/set/list/reset/path subcommand grammar and the output formatting live entirely in the plugin (`candy/plugin-settings/{command.go,provider.go,plugin.go}`). The config subsystem stays in core: reading and writing the runtime config file `~/.config/charly/config.yml` (`charly/runtime_config.go` — `GetConfigValue` / `SetConfigValue` / `ListConfigValues` / `ResetConfigValue` / `RuntimeConfigPath`), the credential-store backend, and the runtime-engine resolution. The plugin reaches that core config subsystem over the generic **"settings" HostBuild seam** (`charly/host_build_settings.go`; `spec.SettingsRequest{Op,Key,Value}` → `spec.SettingsReply{Value,Entries,Error}`, `Op ∈ get/set/list/reset/path`; `resolveSettingsGet` carries the `get` special-cases — `engine.*` resolved via `ResolveRuntime`, `secret_backend` via the resolved credential store). `settings` is compiled into the `charly` binary (`charly/charly.yml` `compiled_plugins:`) because its `Invoke(OpRun)` needs the in-proc reverse channel — threaded by `dispatchInProcCommand` — to call `HostBuild("settings")`; the out-of-process path has no reverse channel and errors. This is the same "plugin owns the command + a generic seam for the core-coupled bits" doctrine as `command:clean` and the vm/pod deploy plugins. There is no hidden core-command forward.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Get a setting | `charly settings get <key>` | Show current value |
| Set a setting | `charly settings set <key> <value>` | Update a setting |
| List all | `charly settings list` | Show all settings with values |
| Reset to default | `charly settings reset <key>` | Remove override, use default |
| Config path | `charly settings path` | Print path to config.yml |
| Migrate secrets | `charly secrets migrate-secrets [--dry-run]` | Move plaintext credentials to keyring (externalized to candy/plugin-secrets) |

## Key Settings

| Key | Default | Env Var | Description |
|-----|---------|---------|-------------|
| `engine.build` | `docker` | `CHARLY_ENGINE_BUILD` | Build engine (docker/podman) |
| `engine.run` | `docker` | `CHARLY_ENGINE_RUN` | Run engine (docker/podman) |
| `run_mode` | `quadlet` | `CHARLY_RUN_MODE` | Deployment mode (quadlet/direct) |
| `bind_address` | `127.0.0.1` | `CHARLY_BIND_ADDRESS` | Default bind address for ports |
| `encrypted_storage_path` | `~/.local/share/charly/encrypted` | `CHARLY_ENCRYPTED_STORAGE_PATH` | Base path for gocryptfs volumes |
| `volumes_path` | `~/.local/share/charly/volumes` | `CHARLY_VOLUMES_PATH` | Base path for bind-mounted volumes |
| `secret_backend` | `auto` | `CHARLY_SECRET_BACKEND` | Credential backend (auto/keyring/config) |
| `keyring_collection_label` | *(empty)* | `CHARLY_KEYRING_COLLECTION_LABEL` | Preferred Secret Service collection label. Empty = iterate naturally (default alias → listing order). Set to pin charly to a specific collection in multi-database setups (e.g. KeePassXC with multiple open databases). See `/charly-automation:enc` for the full iteration order. |
| `forward_gpg_agent` | `true` | `CHARLY_FORWARD_GPG_AGENT` | Forward GPG agent into containers |
| `forward_ssh_agent` | `true` | `CHARLY_FORWARD_SSH_AGENT` | Forward SSH agent into containers |
| `hosts.<alias>` | *(none)* | — | SSH target for `charly --host <alias>` remote execution. Free-form: `host`, `user@host`, `user@host:port`. Consulted by the top-level `--host` flag to re-exec `charly` commands on another machine over SSH. See `/charly-core:ssh`. |

## Usage

### Engine Selection

```bash
# Switch to podman for both build and run
charly settings set engine.build podman
charly settings set engine.run podman

# Check current engine
charly settings get engine.build
```

### Storage Paths

```bash
# Change volume storage to NAS
charly settings set volumes_path /mnt/nas/charly-volumes

# Change encrypted storage location
charly settings set encrypted_storage_path /mnt/encrypted/charly
```

### Secret Backend

```bash
# Force the Secret Service keyring backend (incl. KeePassXC via FdoSecrets)
charly settings set secret_backend keyring

# Force the config-file plaintext fallback (headless hosts)
charly settings set secret_backend config

# Migrate plaintext secrets from config.yml to the keyring (the credential
# store + secrets CLI are externalized into candy/plugin-secrets)
charly secrets migrate-secrets

# Preview migration without changes
charly secrets migrate-secrets --dry-run
```

### Resolution Chain

Settings resolve in this order: environment variable > config.yml > default value.

## Cross-References

- `/charly-core:charly-config` -- deployment configuration (uses settings)
- `/charly-build:secrets` -- credential management
- `/charly-core:charly-doctor` -- diagnose settings and secret storage health
- `/charly-automation:enc` -- encrypted volume paths
