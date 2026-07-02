---
name: agent-forwarding
description: |
  Agent forwarding support -- GPG, SSH, and direnv for .secrets workflow.
  Use when working with agent forwarding, SSH/GPG socket forwarding, or the agent-forwarding candy.
---

# agent-forwarding -- SSH/GPG Agent Forwarding Support

**Pure composition candy.** This candy carries no
shell config of its own; per-tool shell init lives in each tool's home
candy and is inherited transitively via `require:`. Specifically:

- **direnv hook** (bash/zsh/fish) → `direnv` candy's `shell:` block.
- **`SSH_AUTH_SOCK` redirect to KeePassXC's published agent socket** →
  `keepassxc-keyring` candy's `shell:` block (target:local only).
- **`GPG_TTY=$(tty)` for the pinentry-qt → libsecret → KeePassXC chain**
  → `keepassxc-keyring` candy's `shell:` block.

Putting any of these in `agent-forwarding` would scatter ownership: the
direnv hook isn't a KeePassXC concern, KeePassXC's socket isn't a GPG
concern. The composition stays declarative; agent-forwarding pulls
in `gnupg` + `direnv` + `ssh-client` and inherits whatever each
contributes.

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (metalayer) |
| Composition | `gnupg`, `direnv`, `ssh-client` |

## Usage

```yaml
# charly.yml
my-image:
  candy:
    base: fedora
  my-image-candy:
    candy:
      - agent-forwarding
```

Included in all application boxes (27 total). Not included in base images (`fedora`, `arch`) or builder images (`fedora-builder`, `arch-builder`).

## How Agent Forwarding Works

Agent forwarding is a **runtime** feature — sockets are bind-mounted from the host into the container at `charly shell` / `charly start` (direct mode) invocation time. This layer provides the container-side binaries (`gpg`, `ssh`, `direnv`) needed to use the forwarded sockets.

### SSH Agent Forwarding

```
Host: $SSH_AUTH_SOCK (any path)
  → Container: /run/host-ssh-auth.sock
  + SSH_AUTH_SOCK=/run/host-ssh-auth.sock (env var)
```

The container's `ssh` and `git` commands automatically use the host's SSH keys. No SSH agent runs inside the container.

**Verification:** `charly shell <image> -c 'ssh-add -l'` lists host SSH keys.

### GPG Agent Forwarding

```
Host: S.gpg-agent (detected via gpgconf --list-dirs agent-socket)
  → Container: $HOME/.gnupg/S.gpg-agent (HOME from ai.opencharly.home label)
```

The container's `gpg` finds the forwarded socket at its standard path. Private key operations (signing, decryption) go through the host's agent. No GPG agent or keyboxd runs inside the container.

**The container has its own keyring.** Public keys must be imported separately:

```bash
# Export from host, import into container
gpg --export --armor KEY_ID | charly shell <image> -c 'gpg --import'
```

**Verification:** `charly shell <image> -c 'gpg-connect-agent --no-autostart /bye'` connects to the host agent (shows "restricted mode" — this is normal for forwarded agent sockets).

### Why NOT Quadlet

Agent socket paths are **session-bound** — they live under `$XDG_RUNTIME_DIR` and change between SSH sessions, reboots, and users. Quadlet `.container` files are static systemd units generated once. Baking socket paths into quadlets would cause boot failures on headless servers managed via SSH.

**Agent forwarding is intentionally excluded from quadlet mode.** Use `charly shell` or `charly start` (direct mode) for agent access.

## Settings

| Setting | Default | Env Var | Description |
|---------|---------|---------|-------------|
| `forward_gpg_agent` | `true` | `CHARLY_FORWARD_GPG_AGENT` | Forward host GPG agent socket |
| `forward_ssh_agent` | `true` | `CHARLY_FORWARD_SSH_AGENT` | Forward host SSH agent socket |

```bash
charly settings set forward_gpg_agent false    # Disable GPG forwarding globally
charly settings set forward_ssh_agent false    # Disable SSH forwarding globally
charly settings reset forward_gpg_agent        # Re-enable (back to default: true)
```

### Per-Box Override (charly.yml)

```yaml
# ~/.config/charly/charly.yml
immich:
  candy:
    forward_gpg_agent: false    # No GPG needed for photo management
    forward_ssh_agent: false    # Security: no host SSH access
charly-fedora:
  candy:
    forward_gpg_agent: true     # Explicit (same as default)
```

Resolution chain: charly.yml per-box > global setting > default (true).

## Where Forwarding is Applied

| Command | Volumes (mounts) | Env vars | Notes |
|---------|-------------------|----------|-------|
| `charly shell` (new container) | Yes | Yes | Full forwarding |
| `charly shell` (exec into running) | No | Yes | Env only; sockets from start time |
| `charly start` (direct mode) | Yes | Yes | Full forwarding |
| `charly cmd` | No | Yes | Exec into running container |
| `charly config` / quadlet | No | No | Intentionally excluded |

## Used In Boxes

charly-arch, arch-test, comfyui, charly-fedora, fedora-test, githubrunner, immich, immich-ml, jupyter, nvidia, ollama, openclaw, openclaw-full, python-ml, selkies-desktop, selkies-labwc-nvidia, sway-browser-vnc, unsloth-studio, valkey-test

## Related Candies

- `/charly-infrastructure:gnupg` -- GnuPG encryption tools (part of this metalayer)
- `/charly-coder:direnv` -- direnv environment loader (part of this metalayer)
- `/charly-infrastructure:ssh-client` -- OpenSSH client (part of this metalayer)
- `/charly-coder:sshd` -- SSH server (separate, for images that need inbound SSH)
- `/charly-infrastructure:gocryptfs` -- encrypted filesystem (separate credential system)

## Cross-References

- `/charly-build:secrets` -- `charly secrets gpg` for managing `.secrets` files, GPG key management (`import-key`, `export-key`, `setup`, `doctor`), KeePassXC integration; credential store for container secrets
- `/charly-core:shell` -- where SSH/GPG agent forwarding happens at runtime
- `/charly-core:service` -- `charly start` direct mode forwarding
- `/charly-core:charly-config` -- `forward_gpg_agent`, `forward_ssh_agent` settings
- `/charly-core:deploy` -- per-box forwarding overrides in charly.yml

## Source

`charly/agent_forward.go` (socket detection, mount resolution), `charly/runtime_config.go` (settings).

## When to Use This Skill

**MUST be invoked** when the task involves SSH or GPG agent forwarding, the `.secrets` + direnv workflow inside containers, or the `agent-forwarding` candy. Invoke this skill BEFORE reading source code.

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
