---
name: gocryptfs
description: |
  Encrypted filesystem (gocryptfs) for charly config encrypted volume operations.
  Use when working with encrypted volumes, charly config mount/unmount, or filesystem encryption.
---

# gocryptfs -- Encrypted filesystem support

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |

## Packages

RPM: `gocryptfs`

## Cross-distro coverage

`rpm:` (Fedora), `pac:` (Arch — community), `deb:` (Debian/Ubuntu — `gocryptfs` available in Debian main) — full parity.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - gocryptfs
```

Typically used as part of the `charly` candy (the full toolchain: charly binary + virtualization + gocryptfs + socat) rather than directly.

## Runtime Behavior

When `charly config mount` or `charly start` mounts encrypted volumes, each gocryptfs daemon runs inside a `systemd-run --scope --user --unit=charly-enc-<image>-<volume>` scope unit. This decouples the FUSE mount lifecycle from the container service — mounts survive container stop/restart and remain browsable on the host.

The `-allow_other` flag is always passed to gocryptfs (required for rootless podman with `--userns=keep-id`). gocryptfs auto-enables `default_permissions`, so kernel UNIX permission checks still apply.

See `/charly-automation:enc` for full encrypted volume operations documentation.

## Used In Boxes

- Part of the `charly` candy's full toolchain (used in `githubrunner`)

## Related Candies

- `/charly-infrastructure:virtualization` -- part of the `charly` candy alongside gocryptfs
- `/charly-infrastructure:socat` -- part of the `charly` candy alongside gocryptfs

## When to Use This Skill

Use when the user asks about:

- Encrypted volumes or filesystems
- `charly config` encrypted volume operations (mount, unmount, status, passwd)
- The `gocryptfs` candy
- systemd scope units for encrypted mounts (`charly-enc-*`)

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, env_provide, tests block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block
