---
name: enc
description: |
  Topic skill for encrypted storage through `charly config`. MUST be invoked for gocryptfs, the `--encrypt` and encrypted-volume flags, config mount/unmount/status/passwd, or Charly encrypted-volume systemd units.
---

# Enc - Encrypted Storage

## Overview

Encrypted volume backing is configured at deploy time via `charly config --encrypt <volume>`. Gocryptfs-encrypted volumes store sensitive data (credentials, keys, configs) with transparent encryption at rest. The cipher directory lives on disk; the plain directory is mounted on demand. `charly config <image>` handles initialization and mounting during deployment setup. `charly start` mounts encrypted volumes inline before starting the container.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Configure encrypted | `charly config <image> --encrypt <vol>` | Set volume backing to encrypted |
| Setup (init + mount) | `charly config <image>` | Initialize cipher dirs and mount encrypted volumes |
| Mount | `charly config mount <image>` | Mount encrypted volumes |
| Unmount | `charly config unmount <image>` | Unmount encrypted volumes |
| Status | `charly config status <image>` | Show mount status |
| Change password | `charly config passwd <image>` | Change encryption password |

All commands accept `--volume NAME` to target a specific volume (otherwise all encrypted volumes are affected).

## Configuration

Encrypted volumes are configured at deploy time, not build time. Use `charly config --encrypt` to set a candy-declared volume's backing to encrypted:

```bash
# Configure "library" volume as encrypted
charly config immich --encrypt library

# Or via canonical syntax
charly config immich -v library:encrypted

# Or via env var
CHARLY_VOLUMES_IMMICH="library:encrypted" charly config immich --password auto
```

This saves to charly.yml:
```yaml
volumes:
  - name: library
    type: encrypted
```

Rules:
- Volume must be declared in `charly.yml` (or provided as deploy-only with `path:`)
- `name`: matches a candy volume name, must match `^[a-z0-9]+(-[a-z0-9]+)*$`

### Per-Volume Explicit Path

Each encrypted volume can specify its own storage directory:

```bash
# Explicit per-volume paths (each volume gets its own directory)
charly config immich-ml \
  --volume library:encrypt:/mnt/nas/immich/library \
  --volume pgdata:encrypt:/mnt/nas/immich/pgdata

# Canonical syntax
charly config immich-ml -v library:encrypted:/mnt/nas/immich/library
```

The path is the **direct volume directory** — `cipher/` and `plain/` are created inside it:
```
/mnt/nas/immich/library/
  cipher/    # gocryptfs encrypted data
  plain/     # FUSE mount point
```

Without an explicit path, the global `encrypted_storage_path` is used with an `charly-<image>-<name>` prefix (backward compatible).

## Storage Layout

### Default (no explicit path)
```
~/.local/share/charly/encrypted/
  charly-<image>-<name>/
    cipher/    # Encrypted data (always on disk)
    plain/     # Decrypted mount point (mounted on demand)
```

Override base path: `charly settings set encrypted_storage_path /path/to/storage` or `CHARLY_ENCRYPTED_STORAGE_PATH=/path`.

## Commands

### Setup (charly config)

```bash
charly config my-app --encrypt secrets              # Set volume as encrypted + init + mount
charly config my-app --password auto                # Auto-generate password
charly config my-app --password manual              # Prompt for password
```

`charly config <image>` handles both initialization (creating cipher directories) and mounting in a single step. If volumes are already initialized, it mounts them. Password is cached in kernel keyring for multi-volume images.

### Mount

```bash
charly config mount my-app                    # Mount all encrypted volumes
charly config mount my-app --volume secrets   # Mount specific volume
```

Prompts for password (or reuses from keyring). Each volume is mounted inside a transient systemd scope unit (`charly-enc-<image>-<volume>.scope`) via `systemd-run --scope --user`. The plain directory becomes available for container use. Scope units can be listed with `systemctl --user list-units 'charly-enc-*'`.

### Unmount

```bash
charly config unmount my-app                    # Unmount all
charly config unmount my-app --volume secrets   # Unmount specific
```

Unmount calls `fusermount3 -u` then stops the scope unit (`systemctl --user stop charly-enc-<image>-<volume>.scope`) to clean up the gocryptfs daemon.

### Status

```bash
charly config status my-app
# secrets: mounted
# configs: not mounted
```

### Change Password

```bash
charly config passwd my-app
```

Changes the gocryptfs password for all encrypted volumes of an image.

## Single Password

When an image has multiple encrypted volumes, `charly config`, `charly config mount`, and `charly start` all use `systemd-ask-password --id=charly-<image>` to cache the passphrase in the kernel keyring. Password is prompted once and reused for all volumes.

## Credential lookup — iteration-capable `ssClient`

**Why iteration matters:** a Secret Service client that looks up credentials
via the `default` alias **only** (no iteration) fails entirely when that alias
resolves to a broken or stub collection — commonly seen with KeePassXC's
FdoSecrets plugin when a previously-exposed database is unloaded. Such a client
would hang `charly config mount` forever polling for a keyring that can't serve the
secret, and a quadlet unit with `TimeoutStartSec=0` would wedge in
`activating (start-pre)` indefinitely.

The credential store is EXTERNALIZED into the out-of-process `candy/plugin-secrets`
plugin (the C2 dep-shed; `go-keyring` no longer links into charly's core). The plugin
ships its own minimal godbus-based Secret Service client
(`candy/plugin-secrets/secret_service.go`, the `ssClient` type) with a three-step
iteration in `findItemAcrossCollections`:

1. Try the collection at the `default` alias (if healthy — skipped if its
   property reads error out).
2. Try a collection matching the `keyring_collection_label` setting (if
   non-empty — see `/charly-build:settings`). Useful for pinning a specific
   collection by label in multi-database setups.
3. Try every other healthy collection in listing order.

Broken collections are skipped with a diagnostic line to stderr:

    charly: skipping broken Secret Service collection <path>: <error>
    charly: Secret Service default alias target <path> is unhealthy; falling back to collection iteration

The client returns `ErrSSNotFound` if no collection has the credential, and
`ErrSSAllBroken` if every candidate errored on unlock or search (distinct
from "credential simply not stored").

**Call path:**

    KeyringStore.Get
      → keyringGetViaSSClient
        → newSSClient()
        → ssClient.findItemAnyCollection(service, username, preferLabel)
          → readAlias("default") → health check → candidate
          → collections() → filter by preferLabel → candidate
          → collections() → filter healthy, dedup vs already-tried → candidates
          → for each candidate: unlock → SearchItems({service, username}) → first match wins
        → ssClient.getSecret(item) → []byte

**Source:** `candy/plugin-secrets/secret_service.go` (ssClient + findItemAcrossCollections),
`candy/plugin-secrets/credential_keyring.go` (the `KeyringStore.Get` entry point that
delegates to ssClient). Covered by the unit tests in
`candy/plugin-secrets/secret_service_test.go` including default-alias-healthy,
default-alias-broken-fallback-to-iteration, preferLabel routing, all-broken
→ ErrSSAllBroken, not-found-anywhere → ErrSSNotFound, search/unlock errors,
and candidate dedup. charly's core reaches them over `verb:credential` (the
`charly/credential_plugin.go` adapter).

## Credential source semantics

`ResolveCredential` (the core adapter `charly/credential_plugin.go`; the env check + the
env-less store chain `resolveStoreChain` in `candy/plugin-secrets/store.go`) returns a
`(value, source)` pair where the source string is one of:

| Source | Meaning | Caller reaction |
|---|---|---|
| `env`         | Resolved from an env var override (e.g. `GOCRYPTFS_PASSWORD`) | Terminal: use the value |
| `keyring`     | Found in the system keyring via the iteration-capable read path | Terminal: use the value |
| `config`      | Found in `~/.config/charly/config.yml` (fallback or explicit backend) | Terminal: use the value |
| `locked`      | Primary backend is present but locked (e.g. keyring not yet unlocked after login) | **Retry** — backend may unlock shortly |
| `unavailable` | Primary backend probe failed (e.g. ssClient saw every collection error out); fell back to `ConfigFileStore` but the credential isn't stored there either | **Retry with backoff** — may be transient at early boot |
| `default`     | Backend queried successfully and the credential is **not stored anywhere** | **Terminal** — prompt the user interactively or fail with remediation |

**The critical distinction** is between `default` and `unavailable`: both
look identical from the ConfigFileStore return value (empty string, nil
error), but they have opposite recovery semantics. Conflating them — polling
forever on both — would wedge `charly-<image>.service` under `TimeoutStartSec=0`
whenever the keyring is broken, so the two are kept distinct.

**Under systemd (`INVOCATION_ID` set, typical for `ExecStartPre`):**

- `default` → **fail immediately** with an actionable error ("encryption
  passphrase not stored for charly/enc/<image>; store with `charly secrets set charly/enc
  <image>`, or switch backend with `charly config set secret_backend config`").
- `locked` / `unavailable` → **retry** up to `encMountDeadline` (package
  variable in `charly/enc.go`, default `2 * time.Minute`, poll period
  `encMountPollPeriod = 5 * time.Second`). After the deadline elapses, fail
  with a diagnostic listing backend, source, and remediation.
- `env` / `keyring` / `config` with a non-empty value → return
  immediately.

**In interactive mode** (no `INVOCATION_ID`), `resolveEncPassphraseForMount`
delegates to `resolveEncPassphrase` which prompts via the extpass script on
the controlling TTY.

Covered by table tests in `charly/enc_resolve_mount_test.go` (7 cases including
`default` fails fast, `locked` retries until deadline, `unavailable` retries
until deadline, `keyring`/`config` with values return immediately, explicit
non-keyring backend fails fast without polling, reset callback invocation).

## Troubleshooting: broken Secret Service collection

**Symptom:** `charly config mount <image>` hangs, or a service's `ExecStartPre`
phase blocks in `activating (start-pre)` state. `journalctl --user -u
charly-<image>.service` shows lines like:

    charly-<image>[...]: charly: Secret Service default alias target <path> is unhealthy; falling back to collection iteration

Or `charly doctor` reports:

    [!] Secret Service collections -- N healthy + 1 broken. Broken: /org/freedesktop/secrets/collection/<path>. Healthy: "<label>"
    [!] Keyring index consistency -- <N indexed, <M> missing: charly/enc/<image>...

**Cause:** KeePassXC's FdoSecrets plugin can advertise a **stub collection**
(commonly aliased as `default`) whose every DBus method call returns
`org.freedesktop.Secret.Error.NoSuchObject` or an `Input/output error`. The
real credentials are in a sibling collection with a different label. This
pattern has been observed when a KeePassXC database was previously exposed
via FdoSecrets but later unloaded or renamed, while the collection entry
lingers in KeePassXC's internal state.

**Fix (nothing to do on the `charly` side):** `ssClient` iterates past the broken
collection automatically and finds the credential in the healthy sibling.
The credential lookup just works. No configuration change needed.

**Optional cleanup (KeePassXC side):**
1. Open KeePassXC
2. Tools → Settings → Secret Service Integration → Exposed Databases
3. Review the list; remove stale entries
4. Restart KeePassXC
5. Re-run `charly doctor` — the "Secret Service collections" check should now
   report "N healthy collection(s)" with no broken count.

**Pinning a preferred collection:** if your setup has multiple healthy
collections and you want `charly` to prefer one by label (e.g. to avoid
iteration overhead), set:

    charly settings set keyring_collection_label "<collection-label>"

`findItemAnyCollection` will try that label-matched collection after the
default alias (if healthy) and before untargeted iteration. Environment
override: `CHARLY_KEYRING_COLLECTION_LABEL`. See `/charly-build:settings` for the full
runtime-config interface.

**Diagnostic direct query (busctl):** to check a specific collection by
path without using charly:

```bash
# List collections
busctl --user call org.freedesktop.secrets /org/freedesktop/secrets \
       org.freedesktop.DBus.Properties Get ss \
       org.freedesktop.Secret.Service Collections

# Read the default alias target
busctl --user call org.freedesktop.secrets /org/freedesktop/secrets \
       org.freedesktop.Secret.Service ReadAlias s default

# Probe a collection's health (should return Label without error)
busctl --user call org.freedesktop.secrets <collection-path> \
       org.freedesktop.DBus.Properties Get ss \
       org.freedesktop.Secret.Collection Label
```

A healthy collection returns its label; a broken stub returns an I/O error.

## Storing the gocryptfs passphrase

Store an encrypted-volume passphrase explicitly in the active credential store
(Secret Service when available, config-file fallback otherwise):

```bash
charly secrets set charly/enc my-app <passphrase>
```

To serve credentials from an existing KeePass database, open it in KeePassXC and
enable the FdoSecrets plugin so its entries appear on the Secret Service bus —
charly's keyring backend reads them like any other collection. See `/charly-build:secrets`
for the full credential-store chain (env → Secret Service keyring → config-file
fallback).

## Scope Unit Architecture

The gocryptfs / `systemd-run --scope` / fusermount3 SHELLING runs OUT of charly's
core: it is served by the compiled-in `candy/plugin-enc` (verb:enc, C16a). charly's
in-core enc shim host-prelifts the resolved per-volume plan + passphrase and Invokes
the plugin's OpExecute; the plugin runs the commands. The runtime behavior below is
unchanged by that extraction.

Each encrypted volume is mounted via `systemd-run --scope --user --unit=charly-enc-<image>-<volume> -- gocryptfs -allow_other <cipherdir> <plaindir>`. This creates a transient systemd scope unit that:

- **Survives container stop/restart** — scope units are independent of the container service's cgroup, so `KillMode=mixed` on service stop does not kill gocryptfs
- **Keeps mounts browsable on host** — the host user can access `plain/` directories even when the container is stopped
- **Handles stale scopes** — if a scope persists from a crash, the next mount attempt stops the stale scope and retries
- **Cleans up on unmount** — `charly config unmount` calls `fusermount3 -u` then `systemctl --user stop charly-enc-<image>-<volume>.scope`. The same teardown is available as a one-shot from the stop verb via `charly stop <image> --unmount` (see `/charly-core:stop`); plain `charly stop` deliberately leaves scopes running because the next start fast-paths through the `charly config mount` short-circuit.

Scope unit naming: `charly-enc-<image>-<volume>.scope` (e.g., `charly-enc-immich-ml-library.scope`).

List active scopes: `systemctl --user list-units 'charly-enc-*'`

### Why `-allow_other` is Required

Rootless podman with `--userns=keep-id` creates a two-level user namespace. During container mount setup, crun runs as inner uid 0, which maps through the namespace chain to **host uid 524288** (a subordinate uid), not the FUSE mount owner (uid 1000). FUSE's kernel check rejects access. The `-allow_other` flag bypasses this check, allowing crun to bind-mount from the FUSE filesystem. gocryptfs auto-enables `default_permissions` with `-allow_other`, so kernel UNIX permission checks still apply (0700 dirs restrict access to the mount owner). Confirmed by podman issues #14488, #15314, #16350, #25894.

### Host prerequisite: `user_allow_other` in `/etc/fuse.conf`

Because every mount uses `-allow_other`, the host's `/etc/fuse.conf` MUST contain an active
`user_allow_other` line — `fusermount3` refuses `-allow_other` for a non-root user without it
(`option allow_other only allowed if 'user_allow_other' is set`). charly handles this proactively:
`charly doctor`'s **Encrypted Storage** group checks it (`checkFuseAllowOther`, WARNING + fix hint
when missing), and the in-core enc shim **preflights** it before a mount/ensure op
(`fuseAllowOtherEnabled` in `charly/enc.go`) — failing fast with the exact fix
(`echo user_allow_other | sudo tee -a /etc/fuse.conf`) instead of the raw `fusermount3` error
mid-mount. Enable it once per host that runs charly encrypted volumes.

## Integration with Runtime

- **`charly shell`/`charly start` (direct mode)**: resolves volume backing from charly.yml, verifies encrypted volumes are mounted, appends `-v <plain>:<container-path>` flags. `charly start` mounts encrypted volumes inline via systemd-run scopes before starting the container
- **`charly config` (quadlet mode)**: generates quadlet file with `ExecStartPre=charly config mount <image>` for encrypted services. ExecStartPre creates scope units internally — these are independent of the container service. Boot behavior is backend-gated (see below)
- **`charly remove --purge`**: removes named volumes
- **Data provisioning**: `charly config --seed` (default) provisions data from data candies into bind-backed directories after mounting encrypted volumes. Works for both bind and encrypted volume types

### Boot Behavior: Backend-Gated

| Credential Backend | Quadlet Behavior | User Action on Reboot |
|---|---|---|
| **Secret Service (keyring)** | `WantedBy=default.target` + `ExecStartPre` (waits for keyring) + `TimeoutStartSec=0` | None — auto-starts after login |
| **Config file / none** | `ExecStartPre` (guard) + NO `WantedBy` | `charly start <image>` (prompts interactively) |

**Secret Service flow on reboot:**
1. Boot → systemd starts user instance (linger) → quadlet service starts
2. ExecStartPre → `charly config mount` → keyring locked → the core RPCs
   `verb:credential await-unlock` to candy/plugin-secrets, which subscribes to
   DBus `PropertiesChanged` signals on Secret Service collections, with a
   30-second backstop re-probe (`awaitSignalBackstop`)
3. User logs in → PAM unlocks GNOME Keyring / KeePassXC unlocks database
4. DBus signal fires (or backstop re-probes) → passphrase found → volumes
   mount → container starts
5. The wait is **unbounded** — charly blocks until the keyring unlocks or
   systemd sends SIGTERM on `systemctl stop`. No arbitrary deadline.

**Event-driven keyring waiting:** when
`source=locked` under a keyring-capable backend, the core's
`resolveEncPassphraseForMount` RPCs `verb:credential await-unlock` to
candy/plugin-secrets — the Secret Service owner since the godbus dep-shed
(charly's core links no godbus). The plugin subscribes to DBus
`org.freedesktop.DBus.Properties.PropertiesChanged` signals on the
`/org/freedesktop/secrets/collection/*` namespace; its wait loop blocks
on `select { case <-sigCh | case <-backstop | case <-ctx.Done() }` —
zero CPU cost between events. No polling. The blocking gRPC Invoke survives
an unbounded wait (go-plugin sets no keepalive/idle timeout on the local
Unix-socket connection).

- `awaitSignalBackstop` — safety-net re-probe interval (default
  `30 * time.Second`). Catches unlock events when the Secret Service
  provider does not emit `PropertiesChanged` (KeePassXC's FdoSecrets
  plugin does NOT emit this signal; GNOME Keyring and KDE Wallet do).
  The backstop is what catches the unlock on KeePassXC hosts.
- `awaitProgressLogInterval` — throttle for periodic "still waiting"
  journal output (default `1 * time.Hour`).
- SIGTERM cancellation: the core builds the wait ctx via
  `signal.NotifyContext(ctx, SIGINT, SIGTERM)` and passes it on the
  Invoke — `systemctl stop` sends SIGTERM, the ctx cancels, gRPC
  propagates the cancellation to the plugin's Invoke, the loop returns
  cleanly, and systemd transitions the unit to `inactive`.
- If the DBus session bus is unavailable (edge case: linger-based start
  before graphical session), the plugin falls back to backstop-only
  polling at the same `awaitSignalBackstop` cadence — still unbounded,
  still low-resource.

Source: `candy/plugin-secrets/keyring_unlock_wait.go` (`awaitUnlock`,
`awaitUnlockLoop`, `awaitUnlockBackstopOnly`, `isCollectionUnlockedSignal`),
reached via `verb:credential await-unlock`. The core seam is
`charly/enc.go` (`awaitKeyringUnlockViaPlugin`) +
`charly/credential_plugin.go` (`pluginCredentialStore.awaitUnlock`, the
`credentialAwaiter` interface).

**Bounded retry for `source=unavailable`:** transient
backend-probe failures (`source=unavailable`) use a bounded poll
loop with two package-level variables in `charly/enc.go`:

- `encMountDeadline` — total wall-clock cap (default `2 * time.Minute`)
- `encMountPollPeriod` — interval between probes (default `5 * time.Second`)

`source=default` (credential not stored anywhere) is terminal and fails
immediately with an actionable error — no amount of retrying will conjure
a credential that was never stored.

**Crash recovery:** FUSE mounts survive container restarts because scope
units are independent of the container service cgroup. On restart, the
`ExecStartPre=charly config mount` step hits the **fast-path short-circuit**:

    All encrypted volumes for <image> already mounted (N/N)

When every requested volume is already mounted, `encMount` at
`charly/enc.go:232-291` iterates the mount list once, finds every target is
live, and returns `nil` **without calling `resolveEncPassphraseForMount`
or touching the credential store at all**. This means a broken keyring
backend does NOT block restarts of running services — only fresh mounts
(e.g., after reboot) need the keyring. If gocryptfs crashes (scope dies),
the next `charly config mount` or `charly start` detects the stale scope, stops
it, and remounts fresh — at which point the iteration-capable ssClient
kicks in.

## Pre-start safety check: cipher populated + plain empty

`verifyBindMounts` (`charly/enc.go:verifyBindMounts`) runs in the `charly start` / `charly shell` direct-mode code path before the container is started. For any `type: encrypted` volume that does not show up as a FUSE mount, an extra discrimination fires before the generic "not mounted" error: when the cipher dir on disk holds user data (anything beyond the `gocryptfs.conf` + `gocryptfs.diriv` metadata files) AND the plain mount target is empty, the error switches to a louder form spelling out the data-loss risk:

```
encrypted volume "library": cipher dir at /home/.../charly-immich-library/cipher is populated but plain mount at /home/.../charly-immich-library/plain is empty — refusing to start (would write plaintext over encrypted data); run 'charly config mount immich' first
```

This guards against a real data-loss shape: a quadlet missing the `ExecStartPre=charly config mount <image>` auto-mount hook (see "Boot Behavior: Backend-Gated" above and `/charly-build:migrate` "charly migrate") would silently bind an empty `plain/` over a populated cipher tree, the container's services would `initdb` / first-run-wizard against the empty dir, and plaintext data would accumulate on top of an encrypted vault. This error class fails the start IMMEDIATELY when `charly start` detects that exact pre-start state.

**Important caveat on quadlet-managed services.** This check runs only in the direct-mode (CLI) path. systemd-managed quadlet services bypass it — they go straight to `podman` after `ExecStartPre=charly config mount <image>` succeeds. The actual root-cause fix for those is the `ExecStartPre` hook itself; verifyBindMounts is a belt-and-suspenders safety net for the direct path.

Helper: `cipherPopulatedPlainEmpty(cipherDir, plainDir)` returns true only when both conditions hold. Returns false on any os.ReadDir error (the surrounding error path will surface those — this helper is purely a discrimination hint). Source: `charly/enc.go:cipherPopulatedPlainEmpty`. Tested by `charly/migrate_quadlets_test.go:TestCipherPopulatedPlainEmpty` (5 sub-cases: dangerous, metadata-only, plain-non-empty, missing-cipher, missing-plain).

## Volume Backing Override

When a volume is configured as `type: encrypted` in charly.yml, it overrides the default named volume. The Docker/Podman named volume is not created -- the gocryptfs mount is used instead.

```yaml
# charly.yml declares a volume:
volumes:
  - name: data
    path: "~/.myapp"

# charly.yml configures it as encrypted:
volumes:
  - name: data
    type: encrypted
```

## Plain (Non-Encrypted) Bind Mounts

For comparison, plain bind mounts use `type: bind`:

```bash
charly config my-app --bind data=/mnt/nas/data    # Explicit host path
charly config my-app --bind data                   # Auto path: ~/.local/share/charly/volumes/my-app/data
```

Plain bind mounts do not use encrypted storage commands. They are direct host directory mounts.

**Source files:**

- `charly/enc.go` — the in-core enc SHIM + deploy-model (C16a). `encMount`/`encUnmount`/`encPasswd`/`ensureEncryptedMounts` are thin shims that HOST-PRELIFT the per-volume plan (`encPlanFor`: resolved cipher/plain dirs + init/mounted flags + scope-unit name) and the passphrase, then `encExecViaPlugin` resolves verb:enc and Invokes OpExecute. Keeps (deploy-model, stays core): `encMount`'s all-mounted short-circuit, `encStatus` (pure probe+print), the path/probe helpers (`encryptedPlainDir`/`isEncryptedMounted`/`isEncryptedInitialized`/`cipherPopulatedPlainEmpty` — the mandatorily-core `ResolveVolumeBacking` + `verifyBindMounts` consume them), `loadEncryptedVolume` (loader), `resolveEncPassphraseForMount` (bounded retry for `source=unavailable` via `retryUnavailable`), `awaitKeyringUnlockViaPlugin` (the `source=locked` waiter — delegates the event-driven DBus wait to `verb:credential await-unlock`, out-of-process in candy/plugin-secrets, so charly's core links no godbus)
- `candy/plugin-enc/enc.go` — the ENCRYPTED-VOLUME (gocryptfs) MECHANICS plugin (C16a, verb:enc, compiled-in): the gocryptfs / `systemd-run --scope --unit=charly-enc-<dir>-<volume>` / fusermount3 / `gocryptfs -init` / `gocryptfs -passwd` / extpass SHELLING (`mountVolumes`/`unmountVolumes`/`ensureVolumes`/`passwdVolumes`/`runGocryptfsScope`/`encExtpassArgs`), driven by the host-prelifted `spec.EncExecInput`. `-allow_other` for rootless keep-id + the stale-scope retry live here. Wire types: CUE-sourced at `sdk/schema/enc.cue`, generated into `spec/cue_types_gen.go` (`#EncExecInput`/`#EncVolumePlan`/`#EncExecReply`, shared by the shim + the plugin); the plain `EncMethod*` string-selector constants stay hand-written in `spec/enc_consts.go` (never a JSON/YAML shape for `gengotypes` to generate)
- `candy/plugin-secrets/keyring_unlock_wait.go` — `awaitUnlock` (the externalized event-driven DBus signal wait for `source=locked`), `awaitUnlockLoop`, `awaitUnlockBackstopOnly`, `isCollectionUnlockedSignal` (the collection-unlocked signal filter), `awaitSignalBackstop` (30s), `awaitProgressLogInterval` (1h)
- `charly/credential_plugin.go` — the core seam: `pluginCredentialStore.awaitUnlock` (RPCs `verb:credential await-unlock` over a SIGINT/SIGTERM-cancellable ctx) + the `credentialAwaiter` interface
- `charly/credential_plugin.go` — the CORE adapter: `DefaultCredentialStore` (→ `pluginCredentialStore`), `ResolveCredential` (the `"unavailable"`-vs-`"default"` source distinction), `resolveSecretBackend`, `resetDefaultCredentialStore` (propagates a keyring re-probe to the plugin over `verb:credential reset`)
- `candy/plugin-secrets/secret_service.go` — godbus-based ssClient, `findItemAcrossCollections` (with locked-vs-broken tracking), `ssOps` interface for test injection, `ErrSSNotFound` / `ErrSSAllBroken` / `ErrSSInteractiveUnlockRequired` sentinel errors
- `candy/plugin-secrets/credential_keyring.go` — `KeyringStore.Probe` (iterates collections, accepts if ≥1 healthy), `KeyringStore.Get` (delegates to `keyringGetViaSSClient`, maps `ErrSSInteractiveUnlockRequired` to `KeyringLockedError`), index-divergence warning
- `candy/plugin-secrets/store.go` — `DefaultCredentialStore` (tracks `defaultStoreProbeErr`), `resolveStoreChain` (the env-less store resolution the core adapter's `ResolveCredential` forwards to over `verb:credential`)
- `charly/deploy.go` — `DeployVolumeConfig`, `ResolveVolumeBacking`
- `charly/runtime_config.go` — `KeyringCollectionLabel` field (the `keyring_collection_label` setting)

## Cross-References

- `/charly-core:deploy` -- Quadlet integration, volume backing configuration, charly.yml
- `/charly-core:charly-config` -- `encrypted_storage_path` and `volumes_path` settings, `charly config mount` short-circuit fast-path documented there too
- `/charly-core:service` -- Container lifecycle, `charly start` inline mount
- `/charly-build:secrets` -- Credential store hierarchy (env → keyring → config), `charly secrets set charly/enc <image>` to store a gocryptfs passphrase explicitly, `charly secrets list` to inspect indexed keys
- `/charly-build:settings` -- `secret_backend`, `keyring_collection_label`, `encrypted_storage_path`, and other runtime config keys that control credential + volume resolution
- `/charly-core:charly-doctor` -- "Secret Service collections" health check, "Keyring index consistency" cross-check; invoke `charly doctor` when diagnosing broken-collection symptoms

## When to Use This Skill

**MUST be invoked** when the task involves encrypted storage, gocryptfs, or encrypted volume backing. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Pre-deployment. Configure encrypted volumes during `charly config`. See also `/charly-core:deploy` (volume backing).
