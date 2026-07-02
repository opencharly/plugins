---
name: debian-coder
description: |
  Kitchen-sink development box on Debian 13 trixie: coding + AI-coding
  CLIs + DevOps tooling in one container. Debian base, 30+ direct candies
  mirroring fedora-coder's stack but with deb: sections. Runs as uid 1000
  (`user`) with passwordless sudo. 143/0 tests pass.
  Use when working with the debian-coder box — or when comparing
  cross-distro parity across the four coder-family boxes.
---

# debian-coder

Debian 13 trixie counterpart of `/charly-coder:fedora-coder`. Same 80-line `check:` block, same ~30 candies, same rootless posture (uid 1000 + passwordless sudo). Key wrinkles are all Debian-specific packaging quirks handled inside individual candies: `bat → batcat` symlink, Microsoft's `dotnet-install.sh` cross-distro installer, and package-existence tests (vs binary-path tests) for `virtualization` because Debian bundles libvirt drivers differently.

> **Location:** lives in the **`opencharly/distro-debian`** repo (git submodule at
> **`box/debian`**), in that repo's config (its `charly.yml` + per-kind
> sibling files). Its `debian` base is owned by the same submodule; its ~31
> candies are pulled by github reference from the main repo. Build/validate from
> the submodule:
> `charly -C box/debian box build debian-coder`, or
> `charly --repo opencharly/distro-debian box build debian-coder`. Deploy-mode verbs
> (`charly config`/`charly start`/`charly check box`) read the built image's OCI labels and
> work from anywhere once it's in local storage.

## Definition

```yaml
debian-coder:
  base: debian
  ports:
    - "2222:2222"                 # sshd-wrapper
    - "18765:18765"               # charly-mcp (Streamable HTTP)
  candy:
    # Baseline
    - agent-forwarding
    - sshd
    - charly
    - charly-mcp
    - container-nesting
    - dbus
    - tmux

    # Language runtimes
    - language-runtimes           # Go + PHP + .NET 9 (via Microsoft dotnet-install.sh)
    - golang
    - nodejs                      # nodejs — Debian's packaged Node
    - rust
    - pixi
    - uv

    # Build + developer tooling
    - build-toolchain
    - dev-tools                   # ripgrep, bat→batcat symlink, fd-find, neovim, …
    - pre-commit
    - direnv
    - gh
    - typst
    - asciinema

    # AI coding CLIs
    - claude-code
    - codex
    - gemini
    - forgecode
    - oracle

    # DevOps / cloud / infra
    - devops-tools
    - kubernetes
    - docker-ce
    - github-actions
    - google-cloud
    - google-cloud-npm
    - grafana-tools
```

## User model — create mode

The `debian:13` upstream base image ships **no** pre-existing uid-1000 account. The embedded `distro.debian` vocabulary declares no `base_user:`, so `user_policy: auto` (the default) falls through to create mode. The bootstrap section of `.build/debian/Containerfile` emits:

```
RUN if ! getent passwd 1000 >/dev/null 2>&1; then
      (getent group 1000 >/dev/null 2>&1 || groupadd -g 1000 user) &&
      useradd -m -u 1000 -g 1000 -s /bin/bash user;
    fi
```

Resolved identity: `User=user, UID=1000, GID=1000, Home=/home/user`. Identical to fedora-coder / arch-coder. Contrast with `/charly-coder:ubuntu-coder` which runs adopt mode on `ubuntu:ubuntu`.

See `/charly-image:image` "user_policy" and `/charly-build:build` "base_user" for the full decision table.

## Security posture

| Field | Value | Source |
|---|---|---|
| `cap_add` | **(empty)** | — |
| `security_opt` | `[unmask=/proc/*]` | `/charly-distros:container-nesting` |
| `devices` | `[/dev/fuse, /dev/net/tun]` | `/charly-distros:container-nesting` |
| `privileged` | `false` | — |
| Network | bridge | defaults |
| UID / user | `1000 / user` | create mode |
| sudo | passwordless via `/etc/sudoers.d/charly-user` (discovered via `getent passwd 1000`) | `/charly-coder:sshd` |

## Debian-specific layer quirks

- **bat → batcat symlink** (`/charly-coder:dev-tools`). Debian and Ubuntu rename `bat` → `batcat` to avoid a namespace collision with a legacy `bacula` utility. The dev-tools candy ships a distro-tolerant cmd task that creates `/usr/bin/bat -> /usr/bin/batcat` when only batcat is present; no-op on Fedora/Arch.
- **dotnet-sdk-9.0 via Microsoft's `dotnet-install.sh`** (`/charly-coder:language-runtimes`). Debian 13 main ships no .NET; Microsoft's trixie apt repo has dotnet-sdk-9.0, but using the official cross-distro `dotnet-install.sh` channel-pin to `9.0` gives version parity with Ubuntu (whose Microsoft noble repo only ships 10.0). Installs to `/usr/share/dotnet` + symlinks `/usr/bin/dotnet`.
- **libvirt tests use `package:` not `file:`** (`/charly-infrastructure:virtualization`). Debian bundles libvirt drivers differently from Fedora's split packaging, so `file: /usr/sbin/virtqemud` would false-fail. The candy probes via `package: libvirt-daemon-driver-qemu` + `package_map:` per-distro package name.
- **sudoers via `getent`** (`/charly-coder:sshd`). Instead of hardcoding `user ALL=…`, the candy runs `getent passwd 1000 | cut -d: -f1` at build time to discover the actual uid-1000 account. On debian-coder that returns `user`; on ubuntu-coder it returns `ubuntu`. One cross-distro implementation, no special cases.

## Test results

`charly check box ghcr.io/opencharly/debian-coder:latest` — **143 passed · 0 failed · 0 skipped**.

Against a live running container, the same command adds live-service extension tests (sshd on 2222, supervisord, dbus, charly-mcp, the libvirt `qemu:///session` daemon — `libvirtd` on Debian, not the Fedora/Arch modular `virtqemud`), mirroring fedora-coder's +18 deploy-scope additions.

## Verification recipe

```bash
# 1. Validate
charly -C box/debian box validate

# 2. Build dependencies auto-resolve (debian → debian-builder → debian-coder)
charly -C box/debian box build debian-coder

# 3. Disposable-container tests
charly check box ghcr.io/opencharly/debian-coder:latest

# 4. Deploy + live tests
charly config debian-coder
charly start debian-coder
charly check box ghcr.io/opencharly/debian-coder:latest

# 5. Clean up
charly stop debian-coder
```

## Ports

| Port | Service | Bound by |
|---|---|---|
| 2222 | sshd-wrapper (SSH access as `user` with sudo) | `/charly-coder:sshd` |
| 18765 | charly-mcp (entire `charly` CLI as MCP tools, Streamable HTTP) | `/charly-coder:charly-mcp` |

Conflicts with the other three coder-family boxes on the same ports — use `-i <instance>` or `-p <remap>` to run alongside.

## Image size

~10.4 GB uncompressed. Comparable to fedora-coder (~14 GB); smaller due to tighter Debian package naming (no split `-devel` packages, sparser optional dependencies pulled by default).

## Cross-distro siblings

All four coder-family boxes share the identical 80-line `check:` block + ~30 identical candies; they diverge only in per-candy package-format sections.

- `/charly-coder:fedora-coder` — RPM (Fedora 43 via fedora-nonfree).
- `/charly-coder:arch-coder` — pacman + optional AUR.
- `/charly-coder:ubuntu-coder` — deb on Ubuntu 24.04; **adopt mode** (`user:ubuntu`).
- `/charly-coder:debian-coder` — this box; create mode (`user:user`).

## Related boxes

- `/charly-distros:debian` — parent base.
- `/charly-distros:debian-builder` — multi-stage builder for pixi/npm/cargo.

## Related layers (Debian-specific content)

- `/charly-coder:sshd` — cross-distro sudoers via `getent passwd 1000`.
- `/charly-coder:dev-tools` — bat → batcat symlink task.
- `/charly-coder:language-runtimes` — Microsoft `dotnet-install.sh` cross-distro pattern.
- `/charly-infrastructure:virtualization` — `package:` + `package_map:` pattern for libvirt.
- `/charly-coder:build-toolchain` — Debian `-dev` package equivalents of Fedora's `-devel`.
- `/charly-coder:gh`, `/charly-coder:docker-ce`, `/charly-coder:kubernetes-layer`, `/charly-distros:container-nesting` — each adds an upstream apt repo (with GPG key) for packages not in Debian main.

## Related commands

- `/charly-core:shell`, `/charly-core:charly-config`, `/charly-core:start`, `/charly-core:stop`, `/charly-check:check`
- `/charly-image:image` — `user_policy:` field reference
- `/charly-build:build` — `base_user:` declaration (absent for Debian)
- `/charly-image:layer` — authoring reference (covers `exclude_distros:`, tag-section `repos:`, Microsoft dotnet-install pattern)

## When to use this skill

**MUST be invoked** when the task involves:

- Building, deploying, or troubleshooting `debian-coder`.
- Comparing cross-distro parity, especially between `debian-coder` and `ubuntu-coder` (the base images differ in their pre-existing user account).
- Understanding why Debian needs the `dotnet-install.sh` shell task (vs Fedora's native `dotnet-sdk` rpm).
- Adding new deb: sections to candies that are currently Fedora/Arch-only.
