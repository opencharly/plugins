---
name: secrets
description: |
  MUST be invoked before any work involving: charly secrets commands, Secret Service / config-file credential management, GPG-encrypted .secrets files, credential import/export, or secret administration.
---

# Secrets - Secret Service & GPG Credential Management

## Overview

`charly` has two distinct secret systems:

1. **Credential store** (`charly secrets get/set/list/delete/import/export`) — keyed
   `service/key` credentials (VNC passwords, layer `secret_*` values) resolved
   from the **Secret Service** (system keyring) with a config-file plaintext
   fallback for headless hosts. Provisioned into Podman secrets at `charly config`
   time.
2. **GPG `.secrets` files** (`charly secrets gpg …`) — project-level shell env vars
   in a GPG-encrypted `.secrets` file, decrypted by direnv on `cd`.

> There is no direct KeePass `.kdbx` file backend. KeePassXC is fully
> supported — but as a **Secret Service** provider (via its FdoSecrets
> plugin), i.e. the keyring backend below, not a `.kdbx` file charly reads
> directly. An existing `.kdbx` serves its secrets with zero data copy once
> exposed through FdoSecrets. The obsolete `secret_backend: kdbx` /
> `secrets_kdbx_*` config keys raise a hard load-time error pointing at
> `charly migrate`.

## Credential Store Hierarchy

Resolution order (first match wins):

| Priority | Backend | When used |
|----------|---------|-----------|
| 1 | Environment variable | `CHARLY_VNC_PASSWORD`, etc. |
| 2 | System keyring (Secret Service) | GNOME Keyring, KDE Wallet, KeePassXC (FdoSecrets) |
| 3 | Config file | Plaintext fallback in `config.yml` (headless last-resort) |

`secret_backend` ∈ {`auto` (default; keyring then config), `keyring`, `config`}.

**Iteration-capable keyring read path:** when the system
keyring backend is active, `charly`'s read path (`KeyringStore.Get` →
`keyringGetViaSSClient` → `ssClient.findItemAnyCollection`) does NOT rely on
the Secret Service `default` alias alone. It iterates all healthy collections,
skipping any that return DBus errors on property reads. This makes charly
resilient to broken `default` alias stubs (commonly seen in KeePassXC
FdoSecrets setups) — credentials stored in a non-default collection are still
findable. Set `keyring_collection_label` via `/charly-build:settings` to pin charly to a
specific collection by label. When every candidate collection is locked
(requires interactive unlock), `source=locked` is returned and
`charly config mount` waits indefinitely via event-driven DBus signal
subscription (zero CPU) until the user unlocks the keyring. See `/charly-automation:enc`
for the full iteration order, source classification, event-driven waiting
behavior, and troubleshooting.

## Quick Reference

All commands below operate on the **active credential store** (Secret Service,
or the config-file fallback) — never a `.kdbx` file.

| Action | Command | Description |
|--------|---------|-------------|
| List entries | `charly secrets list [service]` | List credentials, optionally filter by service prefix |
| Get value | `charly secrets get <service> <key>` | Print credential value |
| Set value | `charly secrets set <service> <key> [value]` | Set credential (prompts if no value) |
| Generate value | `charly secrets set <service> <key> --generate` | Generate 32-char hex random value |
| Delete entry | `charly secrets delete <service> <key>` | Remove an entry |
| Import | `charly secrets import [--dry-run]` | Copy config.yml + keyring credentials into the active store |
| Export | `charly secrets export [--format yaml\|json]` | Export all entries (plaintext!) |

## Subcommand Details

### List

```bash
charly secrets list              # All charly entries (keyring shadow index + config)
charly secrets list charly/vnc       # Filter by service prefix
```

Prints `service/key` pairs, one per line. The listing is the union of the
keyring shadow index (`keyring_keys` in `config.yml`) and the config-file
plaintext entries, so it reflects everything regardless of the active backend.

### Get / Set / Delete

```bash
charly secrets get charly/vnc my-image              # Print value
charly secrets set charly/vnc my-image              # Prompt for value securely
charly secrets set charly/vnc my-image mypassword   # Set value inline
charly secrets set charly/vnc my-image --generate   # Generate and print random value
charly secrets delete charly/vnc my-image           # Remove entry
```

`set`/`delete` operate on the active store (`DefaultCredentialStore()`); `get`
reads the active store. The `--generate` flag produces 16 random bytes as a
32-character hex string, printed to stdout.

### Import

```bash
charly secrets import --dry-run    # Preview what would be imported
charly secrets import              # Copy config.yml + keyring entries into the active store
```

Collects credentials from:
1. **Config file** — plaintext credentials in `config.yml`
2. **System keyring** — entries tracked in `keyring_keys` config list

Copies (does NOT clear the source) into the active store. This differs from
`charly secrets migrate-secrets`, which *moves* config plaintext into the keyring
and strips the plaintext copies.

### Export

```bash
charly secrets export                  # YAML format (default)
charly secrets export --format json    # JSON format
```

**WARNING:** Exports plaintext credentials. Outputs nested map: `service -> key -> value`. Values are resolved through the active store (with config fallback).

## Common Workflows

### First-Time Setup

A running Secret Service provider (GNOME Keyring, KDE Wallet, or KeePassXC with
FdoSecrets enabled) is all that's needed — `secret_backend: auto` finds it. On a
headless host with no Secret Service, charly falls back to the config-file store
automatically.

```bash
charly settings set secret_backend keyring   # (optional) force the keyring backend
charly secrets set charly/secret MY_TOKEN xyz    # store a credential
charly secrets get charly/secret MY_TOKEN        # read it back
```

### Credential-backed layer env vars (`secret_accept` / `secret_require`)

A candy can declare credential-backed env vars in `charly.yml` via the
`secret_accept:` / `secret_require:` sections. At `charly config` time, the
declared values are resolved from the credential store, provisioned as
per-image podman secrets, and injected into the container at runtime via
`Secret=<name>,type=env,target=<var>` directives — **never landing in
`charly.yml` or the generated quadlet as plaintext**. See `/charly-image:layer`
(secret_accept / secret_require) for the authoring side.

The credential store namespace for these entries defaults to `charly/secret`
with the env var name as the key. Layer authors can override with an
explicit `key: charly/api-key/openrouter` in charly.yml, which is useful when
multiple consumers should resolve the same upstream credential (e.g.,
openwebui and hermes both pointing at `charly/api-key/openrouter` so one
`charly secrets set` populates both).

**Storage commands:**

```bash
# Default path (matches charly.yml `secret_accept: [{name: WEBUI_ADMIN_PASSWORD}]`)
charly secrets set charly/secret WEBUI_ADMIN_PASSWORD <password>

# Explicit key path (matches charly.yml `key: charly/api-key/openrouter`)
charly secrets set charly/api-key openrouter sk-or-xxxxxxxx
charly secrets set charly/api-key ollama gsk-yyyyyyyy
charly secrets set charly/api-key immich <immich-key-from-web-ui>
```

**Auto-generated `secret_require:` tokens.**
`secret_require:` entries that miss everywhere (env + credential
store) auto-generate a 32-byte hex token via `generateRandomHex(32)` +
`DefaultCredentialStore.Set`, persisted at `charly/secret/<NAME>` (or the
declared `key:` override). The first deploy that resolves the secret
writes; every subsequent deploy reads the persisted value. Race-free
across multi-layer declarations because `DefaultCredentialStore` caches
via `sync.Once` — when k3s-server and k3s-agent both declare
`K3S_CLUSTER_TOKEN`, whichever resolves first writes, and the other
reads. No operator setup required for `charly update check-k3s-vm` to succeed
on a fresh host.

`secret_accept:` entries do NOT auto-generate (they're optional by
contract; the caller falls back to `dep.Default` when missing). Only
`secret_require:` triggers the auto-gen path.

**Retrieve** an auto-generated value (e.g., to log into a service for
the first time):

```bash
charly secrets get charly/secret K3S_CLUSTER_TOKEN
charly secrets get charly/secret WEBUI_ADMIN_PASSWORD
```

**Override** a `secret_require:` value with a specific value before
the first deploy:

```bash
charly secrets set charly/secret K3S_CLUSTER_TOKEN <value>
```

The auto-gen path is skipped whenever any non-empty value is already
resolvable (env var, keyring, or config-file fallback).

**Persistence venue.** When no keyring is available (headless
first-boot, fresh CI runner), the auto-generated token lands in
`~/.config/charly/config.yml` via `ConfigFileStore` (mode 0600).
Operators on multi-user hosts should run a Secret Service provider
(e.g. KeePassXC with FdoSecrets enabled) BEFORE the first deploy so
subsequent secrets land in the keyring instead of the plaintext
config file.

**Rotation:** update the store and re-run `charly config`. The
`RotateOnConfig` flag on credential-backed secrets bypasses the
`podmanSecretExists` short-circuit, so the podman secret is re-created
with the new value on every `charly config`:

```bash
charly secrets set charly/api-key/openrouter <new-value>
charly config openwebui --update-all
systemctl --user restart charly-openwebui.service
```

**One-shot `-e` import:** the `-e NAME=VAL` CLI flag on `charly config`
auto-imports the value into the credential store when NAME matches a
`secret_accept` / `secret_require` declaration on the target image. The
plaintext is stripped from `c.Env` before it can reach `saveDeployState`
or the quadlet writer. First-time setup:

```bash
charly config openwebui -e WEBUI_ADMIN_PASSWORD=<password> -e OPENROUTER_API_KEY=sk-or-xxx
```

Subsequent `charly config openwebui` resolves from the store without needing
`-e` again.

**Migration from legacy plaintext:** `charly config` automatically moves any
`NAME=VAL` entry in `charly.yml` whose NAME is a `secret_accept` /
`secret_require` declaration on the image into the credential store.
The plaintext is stripped, `charly.yml.bak.<ts>` is written as a rollback
point, and the migration logs each entry on stderr. Idempotent — safe to
run on a clean host.

**Distinction from layer-owned `secret:`:** the charly.yml `secret:`
field (e.g., immich's `db-password`) creates per-image secrets that are
auto-generated once at `charly config` time and never rotated. Credential-
backed `secret_accept` / `secret_require` are user-owned, shareable
across consumers, and refreshed on every `charly config`. Both flow through
the same `Secret=<name>,type=env,target=<var>` quadlet emission; only the
rotation semantics differ. See `/charly-image:layer` (secret_accept / secret_require).

## Config Keys

| Key | Description |
|-----|-------------|
| `secret_backend` | Force backend: `auto` (default; keyring then config), `keyring`, or `config` |
| `keyring_collection_label` | Preferred Secret Service collection label (empty = iterate naturally). Pin charly to a specific collection in multi-database setups. |

## Project-Level Secrets (.secrets + direnv)

Separate from charly's credential store, project-level environment variables (e.g., `GMAIL_USER`, `GMAIL_PASSWORD`) are stored in `.secrets` — a GPG-encrypted file at the project root. direnv decrypts it in memory via `charly secrets gpg env` when entering the directory (`eval "$(charly secrets gpg env)"` in `.envrc`).

**This is NOT managed by the `charly secrets` credential store.** The two systems serve different purposes:

| System | What it manages | How it works |
|--------|----------------|--------------|
| `charly secrets` (Secret Service / config) | Container-level credentials (VNC passwords, service secrets) | Provisioned at `charly config` time into Podman secrets |
| `charly secrets gpg` + direnv | Project-level shell env vars (API keys, credentials) | GPG-encrypted `.secrets` file, decrypted by direnv on `cd` |

## `charly secrets gpg` — GPG-Encrypted .secrets Management

Manage GPG-encrypted `.secrets` environment files directly from the CLI. All commands shell out to `gpg` (must be in PATH).

### Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Show contents | `charly secrets gpg show [-f FILE]` | Decrypt and print to stdout |
| Export for check | `charly secrets gpg env [-f FILE]` | Decrypt .secrets as `export KEY='value'` for check/direnv |
| Edit in editor | `charly secrets gpg edit [-f FILE]` | Decrypt, open `$EDITOR`, re-encrypt |
| Encrypt file | `charly secrets gpg encrypt -r KEY_ID [-i .env] [-o .secrets]` | Encrypt plaintext env file |
| Decrypt file | `charly secrets gpg decrypt [-i .secrets] [-o FILE]` | Decrypt to file or stdout |
| Set a key | `charly secrets gpg set KEY VALUE [-f FILE] [-r KEY_ID]` | Add or update KEY=VALUE |
| Remove a key | `charly secrets gpg unset KEY [-f FILE]` | Remove a key from .secrets |
| Add recipient | `charly secrets gpg add-recipient KEY_ID [-f FILE]` | Re-encrypt with additional recipient |
| List recipients | `charly secrets gpg recipients [-f FILE]` | List GPG key IDs that can decrypt |
| **Import key** | `charly secrets gpg import-key <path>` | Import GPG key from file, directory, or Secret Service |
| **Export key** | `charly secrets gpg export-key [path] [--to-keystore]` | Export GPG key to directory and/or KeePassXC |
| **Setup** | `charly secrets gpg setup` | Configure gpg-agent, import/generate key, store passphrase |
| **Doctor** | `charly secrets gpg doctor [-f FILE]` | Health check: GPG agent, keys, Secret Service, .secrets |

### `charly secrets gpg env`

Decrypt `.secrets` and output `export KEY='value'` lines to stdout. Designed for `eval` or direnv:

```bash
eval "$(charly secrets gpg env)"              # Load secrets into current shell
eval "$(charly secrets gpg env -f .secrets.prod)"  # Load from specific file
```

**Behavior:**
- Silent exit 0 if file doesn't exist (safe for `.envrc` — no error when `.secrets` is absent)
- Parses KEY=VALUE format, skips comments and blank lines, strips surrounding quotes
- Values are single-quoted in output (safe shell escaping via `shellQuote`)
- Replaces the external `dotenv_gpg_if_exists` direnvrc function — no external dependency needed

**Usage in `.envrc`:**
```bash
eval "$(charly secrets gpg env)"
```

### Common Workflows

```bash
# Create .secrets from a plaintext .env file
charly secrets gpg encrypt -r 420DE2B3 -i .env -o .secrets
rm .env

# View contents
charly secrets gpg show

# Add a new secret
charly secrets gpg set API_KEY sk-test-abc123

# Edit in your editor
charly secrets gpg edit

# Remove a secret
charly secrets gpg unset OLD_KEY

# Add another person who can decrypt
charly secrets gpg add-recipient THEIR_KEY_ID

# See who can decrypt
charly secrets gpg recipients
```

### Flags

- `-f, --file` — Path to encrypted file (default: `.secrets` in current directory)
- `-r, --recipient` — GPG key ID (repeatable, required for `encrypt`, optional for `set` on new files)
- `-i, --input` — Input file for encrypt/decrypt (default: `.env` / `.secrets`)
- `-o, --output` — Output file for encrypt/decrypt (default: `.secrets` / stdout)

### `charly secrets gpg import-key` — Import GPG Keys

Import from file, directory, or KeePassXC Secret Service:

```bash
charly secrets gpg import-key ~/Sync/Conf/gpg/           # From directory (all .asc/.gpg + ownertrust.txt)
charly secrets gpg import-key ~/key.asc                   # From single file
charly secrets gpg import-key --from-keystore              # From KeePassXC Secret Service
charly secrets gpg import-key --from-keystore --key-id XX  # Specific key from KeePassXC
charly secrets gpg import-key ~/keys/ --passphrase "xxx"   # With loopback pinentry (no GUI prompt)
```

**Directory import** auto-detects `.asc`, `.gpg`, and `ownertrust.txt` files. **Keystore import** retrieves armored keys stored with schema `org.gnupg.Key` — these are created by `charly secrets gpg export-key --to-keystore`.

The `--passphrase` flag uses GPG's loopback pinentry mode, avoiding the GUI prompt during import.

### `charly secrets gpg export-key` — Export GPG Keys

Export to filesystem and/or KeePassXC:

```bash
charly secrets gpg export-key ~/Sync/Conf/gpg/            # To directory (public.asc, secret.asc, ownertrust.txt)
charly secrets gpg export-key --to-keystore                # To KeePassXC Secret Service
charly secrets gpg export-key ~/backup/ --to-keystore      # Both filesystem and KeePassXC
charly secrets gpg export-key --key-id XXXX --to-keystore  # Specific key
charly secrets gpg export-key --to-keystore --passphrase X # Also store passphrase in Secret Service
```

**Keystore export** stores the armored private key as a Secret Service entry (schema `org.gnupg.Key`, attributes: `keyid`, `uid`). This enables key recovery via `import-key --from-keystore` without filesystem backups.

### `charly secrets gpg setup` — One-Stop GPG Configuration

Configures the full GPG/KeePassXC chain in one command:

```bash
charly secrets gpg setup                                   # Interactive
charly secrets gpg setup --import ~/Sync/Conf/gpg/         # Import key, then configure
charly secrets gpg setup --from-keystore                    # Restore key from KeePassXC
charly secrets gpg setup --passphrase "xxx"                 # Batch mode (no prompts)
```

**Steps performed:**
1. Check prerequisites: `gpg`, `gpg-connect-agent`, `pinentry-qt` (libsecret), `secret-tool`
2. Install `~/.gnupg/gpg-agent.conf` (pinentry-qt, 8h cache, allow-preset-passphrase)
3. Enable systemd socket activation (`gpg-agent.socket`, `gpg-agent-extra.socket`)
4. Restart gpg-agent
5. Import or generate GPG key (RSA-4096, 2-year expiry, git config for name/email)
6. Store passphrase in Secret Service for ALL keygrips (primary + subkeys)
7. Verify encrypt/decrypt round-trip

**Flags:**
- `--import <path>` — Import key from file/directory before setup
- `--from-keystore` — Import key from KeePassXC before setup
- `--passphrase <value>` — Batch mode: generate key + store passphrase without prompts
- `--key-id <id>` — Use specific existing key
- `--skip-secret-service` — Skip passphrase storage in Secret Service

### `charly secrets gpg doctor` — Health Check

Read-only diagnostic of the full GPG/direnv chain:

```bash
charly secrets gpg doctor                    # Check everything
charly secrets gpg doctor -f .secrets.prod   # Check specific file
```

**Checks:** gpg binary, gpg-agent status, gpg-agent.conf (pinentry, cache TTL), systemd sockets, secret keys, Secret Service availability, passphrase storage for each keygrip, key backups in Secret Service, .secrets file recipients and decrypt test.

Returns non-zero exit code if any critical issue found.

## GPG/KeePassXC Integration Architecture

### Passphrase Flow (pinentry-qt ↔ KeePassXC)

```
gpg --decrypt .secrets
  → gpg-agent (needs passphrase for subkey keygrip)
    → spawns pinentry-qt
      → pinentry-qt: secret_password_lookup_nonpageable_sync()
        schema: "org.gnupg.Passphrase", attr: keygrip="<40-char-hex>"
      → KeePassXC returns stored passphrase (if found) → no GUI prompt
      → OR: pinentry-qt shows GUI dialog → user enters passphrase
    → gpg-agent caches passphrase (8h default, 12h max)
  → decryption succeeds
```

**Key facts:**
- pinentry-qt links against libsecret and queries KeePassXC via `org.freedesktop.secrets` D-Bus API
- Passphrase lookup uses schema `org.gnupg.Passphrase` with attribute `keygrip`
- Each GPG key has multiple keygrips (one per key/subkey) — passphrases must be stored for ALL keygrips
- `charly secrets gpg setup` stores passphrases for all keygrips automatically
- gpg-agent's in-memory cache (8h/12h) reduces Secret Service lookups

### Key Storage in KeePassXC

Two Secret Service schemas:
- **`org.gnupg.Passphrase`** — passphrase per keygrip (compatible with pinentry-qt auto-lookup)
- **`org.gnupg.Key`** — armored private key backup (for `import-key --from-keystore` recovery)

Both are standard Secret Service entries visible in KeePassXC's FdoSecrets-exposed group.

### Error Diagnostics

When decryption fails, `charly secrets gpg` now prints actionable diagnostics instead of raw GPG errors:
- Which key ID the file is encrypted for
- Whether the key exists in the local keyring
- Whether the key is backed up in Secret Service (with restore command)
- Agent status, config status, Secret Service availability
- Specific `charly secrets gpg` commands to fix each issue

## Key Management Workflows

### First-Time Setup (New Machine)

```bash
# Option A: Import existing key from backup
charly secrets gpg setup --import ~/Sync/Conf/gpg/

# Option B: Restore from KeePassXC (if key was previously exported)
charly secrets gpg setup --from-keystore

# Option C: Generate fresh key
charly secrets gpg setup
# Then re-encrypt .secrets: charly secrets gpg encrypt -r <NEW_KEY_ID> -i .env -o .secrets
```

### Backup Key to KeePassXC

```bash
charly secrets gpg export-key --to-keystore              # Key backup
charly secrets gpg export-key ~/Sync/Conf/gpg/           # Filesystem backup too
```

### Restore Key on New Machine

```bash
charly secrets gpg import-key --from-keystore            # From KeePassXC
charly secrets gpg setup                                 # Configure agent + store passphrase
```

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gpg: No secret key` | Key not in keyring | `charly secrets gpg import-key <path>` |
| Constant passphrase prompts | Passphrase not in Secret Service | `charly secrets gpg setup` (stores for all keygrips) |
| `decrypting .secrets failed` | Diagnostics printed automatically | Follow suggested `charly secrets gpg` commands |
| `Secret Service not available` | KeePassXC not running/unlocked | Start KeePassXC, unlock database |
| `secret-tool store` fails | No FdoSecrets exposed group | KeePassXC → right-click group → "Mark as Secret Service exposed" |
| Passphrase stored but still prompted | Stored for wrong keygrip | `charly secrets gpg doctor` shows which keygrips need passphrases |

### Using .secrets Inside Containers

For GPG agent forwarding into containers (so `gpg --decrypt` works inside), use the `agent-forwarding` layer. See `/charly-distros:agent-forwarding` for details. The container's GPG uses the host's agent via a forwarded socket — no GPG agent runs inside the container.

## Cross-References

- `/charly-core:charly-config` — `secret_backend` and other settings keys
- `/charly-automation:enc` — encrypted volume credential lookup, iteration-capable ssClient, broken-collection troubleshooting, source classification (`env`/`keyring`/`config`/`locked`/`unavailable`/`default`)
- `/charly-build:settings` — `keyring_collection_label`, `secret_backend`, and other runtime config keys
- `/charly-core:charly-doctor` — Secret Service collection health + shadow index consistency checks
- `/charly-core:service` — container secrets (`secrets` field in charly.yml, provisioned at `charly config`)
- `/charly-distros:agent-forwarding` — SSH/GPG agent forwarding into containers
- `/charly-infrastructure:gnupg` — GnuPG package layer
- `/charly-openwebui:openwebui` — two-tier secrets pattern: podman secrets (`WEBUI_SECRET_KEY` auto-generated) + GPG `.secrets` (API keys)
- `/charly-coder:direnv` — direnv environment loader

## Source

The credential store + the `charly secrets` CLI are EXTERNALIZED into the out-of-process
`candy/plugin-secrets` plugin (the C2 dep-shed that removed `go-keyring` from
`charly/go.mod`): `candy/plugin-secrets/command.go` (the `charly secrets` CLI: list/get/set/
delete/import/export/migrate-secrets), `candy/plugin-secrets/secrets_gpg.go` (GPG `.secrets`
commands + key management + diagnostics), `candy/plugin-secrets/{store,config_store,
credential_keyring,credential_config,secret_service,verb_credential,credential_admin}.go`
(the `verb:credential` backends + the env-less resolve + the doctor health probe). charly's
core keeps only the thin adapter `charly/credential_plugin.go` (`CredentialStore` /
`ResolveCredential` / `DefaultCredentialStore` → `verb:credential`) + `charly/secrets.go`
(podman-secret provisioning). On an
installed host the plugin lives beside charly at `/usr/lib/charly/plugins` (every native
package build — the arch PKGBUILD and the fedora `.rpm` / debian `.deb` builds — bakes the
binary + its `.providers` manifest, off the shared `pkg/host-command-plugins.txt` set).

## When to Use This Skill

**MUST be invoked** when the task involves `charly secrets` commands, Secret Service / config-file credential management, GPG-encrypted `.secrets` file management, GPG key management, Secret Service integration, or credential import/export. Invoke this skill BEFORE reading source code or launching Explore agents.
