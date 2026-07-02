---
name: gnupg
description: |
  GnuPG encryption and signing tools for GPG agent forwarding.
  Use when working with GPG, encryption, signing, or the gnupg candy.
---

# gnupg -- GnuPG encryption and signing tools

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |

## Packages

RPM: `gnupg2` · PAC: `gnupg` · DEB: `gnupg` — full cross-distro parity. Note: `gnupg` is also in the `debian` distro's bootstrap package set (see `/charly-distros:debian`) because downstream candies need `gpg --dearmor` at build time.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - gnupg
```

Typically used as part of the `agent-forwarding` composition candy rather than directly.

## Runtime Behavior

Provides `gpg`, `gpgconf`, `gpg-agent`, `gpg-connect-agent` binaries inside the container. When combined with SSH/GPG agent forwarding (`charly shell`, `charly start` direct mode), the container's GPG uses the host's agent for private key operations (signing, decryption) via a forwarded socket.

The container has its own keyring (public keys must be imported separately with `gpg --import`). No host keyring is mounted — only the agent socket is forwarded.

## Used In Boxes

Part of `agent-forwarding` composition candy, used in 27 application boxes including: `charly-arch`, `charly-fedora`, `nvidia`, `jupyter`, `ollama`, `openclaw`, `immich`, `comfyui`, `selkies-desktop`, and all other non-base boxes.

## Related Candies

- `/charly-distros:agent-forwarding` -- metalayer that includes gnupg + direnv + ssh-client
- `/charly-coder:direnv` -- environment variable loading from .envrc/.secrets
- `/charly-infrastructure:ssh-client` -- OpenSSH client for SSH agent forwarding

## Cross-References

- `/charly-build:secrets` -- `charly secrets gpg` commands: key management (`import-key`, `export-key`), GPG agent setup (`setup`), health check (`doctor`), and `.secrets` file management
- `/charly-core:shell` -- agent socket forwarding happens at `charly shell` invocation time
- `/charly-core:service` -- agent forwarding in `charly start` direct mode

## When to Use This Skill

Use when the user asks about:

- GPG encryption or signing inside containers
- The `gnupg` candy
- GPG agent forwarding
- Importing public keys into container keyrings

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
