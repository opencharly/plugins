---
name: settings
description: |
  Runtime configuration management for the charly CLI.
  MUST be invoked before any work involving: charly settings commands, runtime configuration, engine selection, bind address, storage paths, or secret backend configuration.
---

# charly settings -- Runtime Configuration

## Overview

Manage charly's runtime configuration stored in `~/.config/charly/settings.yml`. Controls engine selection, networking, storage paths, secret backend, and agent forwarding.

`charly settings` is an **external COMMAND-class plugin** (`candy/plugin-settings`, `command:settings`) — one of cutover C15's four remaining welded-command externalizations (after `tmux`/`preempt`/`feature`/`vm`/`doctor`). The user-facing command tree is unchanged; only its CLI registration moved out-of-process. The plugin is a THIN forwarder: charly resolves the `settings` word via the discovered (or `/usr/lib/charly/plugins`-baked) plugin and syscall.Exec's it in CLI mode, which raw-forwards the args to the hidden in-core `charly __settings` command. Because `settings` is a command TREE (get/set/list/path/reset), the plugin raw-forwards every subcommand token through kong passthrough — one forwarder covers the whole tree. The `SettingsCmd` handlers STAY core (`charly/main.go`) because they read and write the runtime config file `~/.config/charly/config.yml` and resolve the credential-store backend + the runtime engine — config machinery an out-of-process plugin cannot reach.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Get a setting | `charly settings get <key>` | Show current value |
| Set a setting | `charly settings set <key> <value>` | Update a setting |
| List all | `charly settings list` | Show all settings with values |
| Reset to default | `charly settings reset <key>` | Remove override, use default |
| Config path | `charly settings path` | Print path to settings.yml |
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

Settings resolve in this order: environment variable > settings.yml > default value.

## Cross-References

- `/charly-core:charly-config` -- deployment configuration (uses settings)
- `/charly-build:secrets` -- credential management
- `/charly-core:charly-doctor` -- diagnose settings and secret storage health
- `/charly-automation:enc` -- encrypted volume paths
