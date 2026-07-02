---
name: charly-arch
description: |
  Arch Linux box with the full charly toolchain. Rootless-first — runs as
  uid=1000 with passwordless sudo (no root, no cap_add: ALL).
  Composes /charly-coder:charly-mcp so the box is reachable as an MCP gateway
  on port 18765. NVIDIA GPU runtime composed in.
  MUST be invoked before building, deploying, configuring, or troubleshooting
  the charly-arch box.
---

# charly-arch

> **Location:** `charly-arch` lives in the **`opencharly/distro-arch`** repo (git
> submodule at **`box/arch`**) and composes its candies by git reference to
> this repo. Build from the submodule: `cd box/arch && charly box build charly-arch`
> (or `charly --repo opencharly/distro-arch box build charly-arch`). The `arch` base +
> `arch-builder` are bare-local in the same self-contained `opencharly/distro-arch`
> submodule (`import: []`) — `base: arch`.

Arch Linux container with the full charly toolchain. Uses the same shared
candy list as `/charly-distros:charly-fedora` — the tag system handles
Arch-specific packages and scripts via `pac:` sections. Composes
`charly-mcp` so the box is addressable as an MCP gateway — LLM agents
can drive build/test/deploy via Streamable HTTP on port 18765.

## Box Properties

| Property | Value |
|----------|-------|
| Base | arch (quay.io/archlinux/archlinux, pinned in the `opencharly/distro-arch` submodule) |
| Tags | `[all, pac, arch]` |
| Candies | agent-forwarding, charly, **charly-mcp**, golang, gh, sshd, container-nesting, nvidia |
| Platforms | linux/amd64 |
| UID / user | **1000 / user** (rootless-first) |
| Network | default `charly` bridge |
| Ports | `2222:2222` (sshd), `18765:18765` (charly-mcp) |
| Security | candy-level only (from `/charly-distros:container-nesting`) |
| Registry | ghcr.io/opencharly |

### Rootless-first posture

All four power-user boxes (`charly-arch`, `/charly-distros:charly-fedora`,
`/charly-coder:fedora-coder`, `/charly-distros:githubrunner`) run rootless because
the `/charly-distros:container-nesting` kernel-level RCA proves that
`unmask=/proc/*` + uid-delegation via subuid/subgid ranges is sufficient for
rootless nested containers + rootless libvirt VMs.

The `/charly-coder:sshd` candy installs `/etc/sudoers.d/charly-user` with
passwordless sudo for `user`, so anything that truly needs root inside
the container is one `sudo` prefix away — but the default user for
every process (sshd session, `charly` commands, nested `podman run`) is
uid=1000.

Resolved OCI security label:

| Field | Value |
|---|---|
| `cap_add` | **(empty)** |
| `security_opt` | `[unmask=/proc/*]` (from `/charly-distros:container-nesting`) |
| `devices` | `[/dev/fuse, /dev/net/tun]` (from `/charly-distros:container-nesting`) |
| `privileged` | `false` |

See `/charly-openclaw:openclaw-desktop` for the sibling rootless-first
box that proves this posture works under streaming-desktop +
nested-VM load, and `/charly-distros:container-nesting` for the kernel
`mount_too_revealing()` RCA.

### Network + port publishing

`charly-arch` uses the project-default `charly` bridge — so `charly-mcp`'s MCP URL
rewriting (`rewriteMCPURLForHost` in `charly/mcp_client.go`) has published port
mappings to work with. (That function also handles host-networked containers
via `HostConfig.NetworkMode` detection, so the bridge isn't strictly required
— but it remains the portable default.) If host-port 2222 is already taken by
another running box (canonical conflict: `/charly-openclaw:openclaw-desktop`
or any `selkies-desktop-*` variant), remap at config time:
`charly config charly-arch -p 2223:2222`.

### MCP gateway (charly-mcp)

The `/charly-coder:charly-mcp` candy deploys `charly mcp serve --listen :18765`
inside the container under supervisord, advertising ~192 MCP tools
(the full Kong CLI surface, including the project-scaffolding +
YAML-editing + file-write authoring verbs). Three deployment patterns
work — bind-mount your project, pin an `CHARLY_PROJECT_REPO`, or rely on the
auto-fallback to `opencharly/charly`:

```bash
# Pattern 1: bind your local checkout
charly config charly-arch --bind project=/home/you/opencharly
charly start charly-arch
charly check live charly-arch --filter mcp  # the baked mcp: call box.list.boxes step lists YOUR project's boxes

# Pattern 3: no bind-mount (auto-fallback kicks in)
charly config charly-arch
charly start charly-arch
charly check live charly-arch --filter mcp  # box.list.boxes lists upstream opencharly/charly boxes
```

Volume NAME is `project` (stable bind-mount API); container PATH is
`/workspace`. See `/charly-coder:charly-mcp` for full deployment patterns,
`/charly-build:charly-mcp-cmd` Part 2 for the server architecture, and `/charly-core:charly-config`
"Bind-mounting a project checkout for charly mcp serve" for the
bind-mount handshake.

## What's Installed

Full charly toolchain via shared candies:

- **charly** — the full toolchain: charly binary + VM tools (qemu-full, virtiofsd, libvirt) + gocryptfs + socat
- **charly-mcp** — MCP server exposing the full charly CLI as tools on :18765 (supervisord-managed; bind `project=` for build-mode tools or rely on auto-fallback)
- **golang** — Go compiler (`go`)
- **gh** — GitHub CLI + `git` + `git-lfs` (single-responsibility; see `/charly-coder:gh`)
- **sshd** — SSH server/client (`openssh` on Arch — `package_map` handles the Fedora/Arch name split) + passwordless sudo for `user`
- **container-nesting** — podman, buildah, crun, fuse-overlayfs, skopeo, tailscale, libsecret + nested container config
- **nvidia** — nvidia-utils, nvidia-container-toolkit (CDI generation; benign pacman-hook NVML noise on GPU-less hosts — see `/charly-distros:nvidia`)

## Lifecycle

```bash
# Build
charly box build charly-arch

# Interactive shell (as uid=1000)
charly shell charly-arch

# Run a command
charly shell charly-arch -c "charly version"
charly shell charly-arch -c "sudo dnf --help"    # sudo works passwordless

# Start as service
charly start charly-arch
charly status charly-arch
charly stop charly-arch
```

## Nested Containers

Rootless podman works inside charly-arch at any nesting depth. The
`/charly-distros:container-nesting` candy provides the config + env vars +
subuid/subgid delegation (1:999 + 1001:64535 per the podman/stable
recipe):

```bash
# Level 1: run containers inside charly-arch
charly shell charly-arch -c "podman run --rm quay.io/libpod/alpine:latest echo hello"

# Level 2: run charly inside charly-arch inside charly-arch
charly shell charly-arch -c "charly shell charly-arch -c 'charly version'"
```

Use `quay.io/libpod/alpine:latest` instead of `docker.io/library/alpine`
to dodge Docker Hub rate limits — the baked
`container-nesting-alpine-run` test does.

## GPU Support

The `/charly-distros:nvidia` candy provides NVIDIA GPU runtime:

- `nvidia-utils` — `nvidia-smi` and driver userspace
- `nvidia-container-toolkit` — `nvidia-ctk` for CDI spec generation

`charly` automatically calls `EnsureCDI()` before launching GPU
containers. GPU access works at any nesting depth.

## Verification

```bash
charly shell charly-arch -c "id"                              # uid=1000(user)
charly shell charly-arch -c "sudo -n whoami"                  # root (passwordless)
charly shell charly-arch -c "charly version"
charly shell charly-arch -c "charly doctor"
charly shell charly-arch -c "podman info"
charly shell charly-arch -c "podman run --rm quay.io/libpod/alpine:latest echo OK"
charly shell charly-arch -c "which nvidia-ctk"
```

## Unified with charly-fedora

Both `charly-arch` and `/charly-distros:charly-fedora` use the exact same candy
list. The tag system (`build: [pac]` + `distro: [arch]` vs
`build: [rpm]` + `distro: ["fedora:43", fedora]`) selects the right
packages and scripts per distro.

## Key Candies

- `/charly-tools:charly` — the full toolchain: charly binary plus VM/encryption tools
- `/charly-coder:charly-mcp` — MCP server gateway (port 18765; `/workspace` bind-mount or auto-fallback)
- `/charly-distros:container-nesting` — nested podman/buildah (pac: podman + crun + buildah; `docker` is RPM-only — Arch gets podman directly)
- `/charly-coder:sshd` — SSH server/client with `package_map` for cross-distro package names + the passwordless-sudo sudoers drop-in
- `/charly-coder:gh` — GitHub CLI + git + git-lfs (owns all git tooling)
- `/charly-distros:nvidia` — NVIDIA GPU runtime

## Related Boxes

- `/charly-distros:arch` — parent base image
- `/charly-distros:charly-fedora` — Fedora counterpart, same candies, same rootless posture
- `/charly-coder:fedora-coder` — kitchen-sink dev sibling (32 candies vs 8; adds coding CLIs + DevOps)
- `/charly-openclaw:openclaw-desktop` — streaming-desktop counterpart (charly toolchain + browser-accessible Wayland); shares the rootless-first posture
- `/charly-distros:githubrunner` — self-hosted GitHub Actions runner; same uid=1000 posture

## Related Commands

- `/charly-core:shell` — open an interactive shell in charly-arch (as uid=1000 with sudo)
- `/charly-core:service` — manage charly-arch as a service
- `/charly-vm:vm` — nested libvirt VMs via `qemu:///session` (rootless)
- `/charly-check:check` — three modes: `charly check box <ref>` (build-scope, disposable container), `charly check live <name>` (full-stack against running deployment), `charly check run <score>` (AI iteration loop)
- `/charly-build:charly-mcp-cmd` — MCP gateway + auto-fallback behavior

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
