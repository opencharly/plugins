---
name: charly-fedora
description: |
  Fedora box with the full charly toolchain using shared candies. Rootless-first —
  runs as uid=1000 with passwordless sudo (no root, no cap_add: ALL). Same candy
  list as charly-arch. Includes NVIDIA GPU runtime.
  MUST be invoked before building, deploying, configuring, or troubleshooting
  the charly-fedora box.
---

# charly-fedora

Fedora container with the full charly toolchain. Uses almost the same
candy list as `/charly-coder:charly-arch` — the tag system handles
Fedora-specific packages and scripts via `rpm:` sections. Supports
nested containers at any depth via `/charly-distros:container-nesting`.

Lives in the **`opencharly/distro-fedora`** repo (git submodule at **`box/fedora`**).
Its `fedora` base is bare-local in the same self-contained submodule
(`import: []`) — `base: fedora`; its
candies (incl. the `nvidia` candy) are pulled by github reference. Build from the
submodule: `charly -C box/fedora box build charly-fedora`. Deploy-mode verbs work
from anywhere once the image is in local storage.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora (quay.io/fedora/fedora:43) |
| Tags | `[all, rpm, fedora, fedora:43]` |
| Layers | agent-forwarding, charly, golang, gh, sshd, container-nesting, nvidia |
| Platforms | linux/amd64 |
| UID / user | **1000 / user** (rootless-first) |
| Network | host |
| Security | layer-level only (from `/charly-distros:container-nesting`) |
| Registry | ghcr.io/opencharly |

### Rootless-first posture

Runs as uid=1000 / `user` with no added capabilities. The
`/charly-distros:container-nesting` kernel RCA establishes that
`unmask=/proc/*` + subuid/subgid delegation is sufficient for rootless
nested containers + rootless libvirt VMs, so this box — like its
power-user siblings (`/charly-coder:charly-arch`, `/charly-coder:fedora-coder`,
`/charly-distros:githubrunner`) — needs no `cap_add: [ALL]` or
`label=disable` / `seccomp=unconfined`.

The `/charly-coder:sshd` candy installs `/etc/sudoers.d/charly-user` with
passwordless sudo for `user`, so anything that genuinely needs root
is one `sudo` prefix away. Default user for every process is uid=1000.

Resolved OCI security label:

| Field | Value |
|---|---|
| `cap_add` | **(empty)** |
| `security_opt` | `[unmask=/proc/*]` (from `/charly-distros:container-nesting`) |
| `devices` | `[/dev/fuse, /dev/net/tun]` (from `/charly-distros:container-nesting`) |
| `privileged` | `false` |

See `/charly-openclaw:openclaw-desktop` (streaming-desktop sibling) and
`/charly-coder:fedora-coder` (kitchen-sink dev sibling) for other boxes
sharing this posture, and `/charly-distros:container-nesting` for the
kernel `mount_too_revealing()` RCA.

### Why still `network: host`

`charly-fedora` uses host networking (unlike `charly-arch`, which uses bridge)
so the box can reach host services and the host namespace directly.
charly-mcp's `rewriteMCPURLForHost` handles host-networked containers via
`HostConfig.NetworkMode=host` detection (see
`charly/mcp_client.go:lookupHostPort`), so host networking does not break
MCP URL rewriting. If you want charly-mcp on charly-fedora, compose it
into the candy list — it will work on either networking mode.

## What's Installed

Full charly toolchain via shared candies:

- **charly** — the full toolchain: charly binary + VM tools (qemu-kvm, qemu-img, libvirt tools) + gocryptfs + socat + gvisor-tap-vsock + podman-machine
- **golang** — Go compiler (`golang-bin`)
- **gh** — GitHub CLI + `git` + `git-lfs` (single-responsibility; see `/charly-coder:gh`)
- **sshd** — SSH server/client (`openssh-server`, `openssh-clients`) + passwordless sudo for `user`
- **container-nesting** — buildah, fuse-overlayfs, shadow-utils, skopeo, tailscale, libsecret + nested container config (Tailscale from `tailscale-stable` repo)
- **nvidia** — nvidia-container-toolkit, libva-nvidia-driver (from negativo17 repo; driver libs provided by CDI at runtime)

## Lifecycle

```bash
# Build (from the opencharly/distro-fedora submodule)
charly -C box/fedora box build charly-fedora

# Interactive shell (as uid=1000)
charly shell charly-fedora

# Run a command
charly shell charly-fedora -c "charly version"
charly shell charly-fedora -c "sudo -n whoami"    # root (passwordless)

# Start as service
charly start charly-fedora
charly status charly-fedora
charly stop charly-fedora
```

## Nested Containers

Rootless podman works inside charly-fedora at any nesting depth. The
`/charly-distros:container-nesting` candy provides the config + env vars +
subuid/subgid delegation per the podman/stable recipe:

```bash
# Level 1: run containers inside charly-fedora
charly shell charly-fedora -c "podman run --rm quay.io/libpod/alpine:latest echo hello"

# Level 2: run charly inside charly-fedora inside charly-fedora
charly shell charly-fedora -c "charly shell charly-fedora -c 'charly version'"
```

Use `quay.io/libpod/alpine:latest` instead of
`docker.io/library/alpine` to dodge Docker Hub rate limits.

## GPU Support

The `/charly-distros:nvidia` candy provides NVIDIA GPU runtime:

- `nvidia-container-toolkit` — CDI spec generation (driver userspace libs provided by CDI at runtime, matching host kernel module)
- `libva-nvidia-driver` — VA-API acceleration

`charly` automatically calls `EnsureCDI()` before launching GPU
containers. GPU access works at any nesting depth.

## Verification

```bash
charly shell charly-fedora -c "id"                  # uid=1000(user)
charly shell charly-fedora -c "sudo -n whoami"      # root
charly shell charly-fedora -c "charly version"
charly shell charly-fedora -c "charly doctor"
charly shell charly-fedora -c "podman info"
charly shell charly-fedora -c "podman run --rm quay.io/libpod/alpine:latest echo OK"
charly shell charly-fedora -c "which nvidia-ctk"

# Verify OCI tags
charly box inspect charly-fedora --format tags
# ["all","rpm","fedora","fedora:43"]
```

## Unified with charly-arch

Both `charly-fedora` and `/charly-coder:charly-arch` use the exact same candy
list. The tag system (`build: [rpm]` + `distro: ["fedora:43", fedora]`
vs `build: [pac]` + `distro: [arch]`) selects the right packages
and scripts per distro.

## Key Candies

- `/charly-tools:charly` — the full toolchain: charly binary plus VM/encryption tools
- `/charly-distros:container-nesting` — nested rootless podman/buildah (authoritative RCA for `mount_too_revealing()` + `unmask=/proc/*`)
- `/charly-coder:sshd` — SSH daemon + passwordless sudo for `user`
- `/charly-coder:gh` — GitHub CLI + git + git-lfs (owns all git tooling)
- `/charly-distros:nvidia` — NVIDIA GPU runtime

## Related Boxes

- `/charly-distros:fedora` — parent base image
- `/charly-coder:charly-arch` — Arch counterpart, same layers, same rootless posture
- `/charly-coder:fedora-coder` — kitchen-sink dev sibling (32 candies, adds coding CLIs + DevOps)
- `/charly-openclaw:openclaw-desktop` — streaming-desktop counterpart (charly toolchain + browser-accessible Wayland); shares the rootless-first posture
- `/charly-distros:githubrunner` — self-hosted GitHub Actions runner; same uid=1000 posture

## Related Commands

- `/charly-core:shell` — open an interactive shell in charly-fedora (as uid=1000 with sudo)
- `/charly-core:service` — manage charly-fedora as a service
- `/charly-vm:vm` — nested libvirt VMs via `qemu:///session` (rootless)
- `/charly-build:charly-mcp-cmd` — MCP gateway deployment patterns (if you add `charly-mcp` to the candies)

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
