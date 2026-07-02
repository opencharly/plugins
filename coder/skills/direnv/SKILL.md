---
name: direnv
description: |
  direnv -- automatic environment variable loading from .envrc files.
  Use when working with direnv, .envrc, .secrets, or environment management.
---

# direnv -- Automatic environment variable loading

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |

## Packages

RPM: `direnv` · PAC: `direnv` · DEB: `direnv` — full cross-distro parity.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - direnv
```

Typically used as part of the `agent-forwarding` composition candy rather than directly. Also available in the heavyweight `dev-tools` candy (46 packages).

## Runtime Behavior

Provides the `direnv` binary AND the per-shell hook installation for automatic environment variable loading from `.envrc` files.

**Shell hooks are declarative.** The candy carries a `shell:` block:

```yaml
shell:
  init: |
    eval "$(direnv hook ${SHELL_NAME})"   # bash/zsh/sh — POSIX-style
  fish:
    init: |
      direnv hook fish | source            # fish — different syntax
```

Container images get `/etc/profile.d/charly-direnv-<shell>.sh` and `/etc/fish/conf.d/charly-direnv.fish` emitted at `charly box build` time. `target: local` host deploys get a managed-block in `~/.bashrc` / `~/.zshrc` plus `~/.config/fish/conf.d/charly-direnv.fish` at `charly bundle add` time, only for shells the runtime probe finds. The fish hook lands in `~/.config/fish/conf.d/charly-direnv.fish` (its own conf.d drop-in), so it works without editing `~/.config/fish/config.fish`.

The primary use case in OpenCharly is the `.secrets` workflow: `.envrc` calls `eval "$(charly secrets gpg env)"` which decrypts a GPG-encrypted `.secrets` file in memory and exports the variables — no plaintext on disk. No external `direnvrc` dependency needed.

## Used In Boxes

Part of `agent-forwarding` composition candy, used in 27 application boxes.

Also available in the `dev-tools` candy.

## Related Candies

- `/charly-distros:agent-forwarding` -- metalayer that includes gnupg + direnv + ssh-client
- `/charly-infrastructure:gnupg` -- GPG tools (needed for `.secrets` decryption)
- `/charly-coder:dev-tools` -- heavyweight candy that also includes direnv (46 packages)

## Cross-References

- `/charly-build:secrets` -- `charly secrets gpg` commands for managing `.secrets` files, `charly secrets gpg setup` for GPG agent + KeePassXC configuration, `charly secrets gpg doctor` for health checks

## When to Use This Skill

Use when the user asks about:

- direnv or `.envrc` files
- The `direnv` candy
- Automatic environment variable loading
- The `.secrets` + direnv workflow

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
