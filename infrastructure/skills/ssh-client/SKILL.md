---
name: ssh-client
description: |
  OpenSSH client tools for SSH agent forwarding.
  Use when working with SSH client, SSH agent forwarding, or the ssh-client candy.
---

# ssh-client -- OpenSSH client tools

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |

## Packages

RPM: `openssh-clients` · PAC: `openssh` · DEB: `openssh-client` (singular — Debian splits client/server, unlike Arch's unified `openssh`).

Note: On Arch Linux, `openssh` is a single package that includes both client and server. The `sshd` candy also installs this package but adds a systemd service and opens port 22. On Debian/Ubuntu, `openssh-client` ships only the client tools; `openssh-server` is a separate package installed by the `sshd` candy.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - ssh-client
```

Typically used as part of the `agent-forwarding` composition candy rather than directly. Use the `sshd` candy instead if you need an SSH *server*.

## Runtime Behavior

Provides `ssh`, `ssh-add`, `ssh-keygen`, `ssh-agent`, `scp`, `sftp` binaries. When combined with SSH agent forwarding (`charly shell`, `charly start` direct mode), the container's SSH commands use the host's SSH agent via a forwarded socket at `/run/host-ssh-auth.sock`.

No SSH agent runs inside the container — the `SSH_AUTH_SOCK` environment variable points to the forwarded host socket.

## Used In Boxes

Part of `agent-forwarding` composition candy, used in 27 application boxes.

## Related Candies

- `/charly-distros:agent-forwarding` -- metalayer that includes gnupg + direnv + ssh-client
- `/charly-coder:sshd` -- SSH server + client (includes systemd service, port 22)
- `/charly-coder:gh` -- GitHub CLI + git (uses SSH for git operations)

## When to Use This Skill

Use when the user asks about:

- SSH client tools inside containers
- SSH agent forwarding
- The `ssh-client` candy
- The difference between `ssh-client` and `sshd` candies

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
