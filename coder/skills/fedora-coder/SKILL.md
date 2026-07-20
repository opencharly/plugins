---
name: fedora-coder
description: |
  Kitchen-sink development box: coding + AI-coding CLIs + DevOps tooling
  in one container. Fedora-nonfree base, 32 direct candies spanning language
  runtimes, build tooling, five AI coding CLIs, and the full cloud/devops
  stack. Runs as uid 1000 with passwordless sudo — rootless-first, matches
  the /charly-openclaw:openclaw-desktop security posture.
  Use when working with the fedora-coder box — specifically any task that
  involves SSH-ing into a single container and having every tool a polyglot
  engineer reaches for during a working day already installed.
---

# fedora-coder

The everyday-development counterpart to `/charly-distros:charly-fedora`: all the
coding + AI + DevOps tooling a developer needs in one box, no desktop,
no streaming. Distinct from `openclaw-desktop` (which adds the
browser-streamed Wayland desktop) — `fedora-coder` is headless and
meant to be accessed via `ssh -p 2222` or `charly shell`.

> **Location:** lives in the **`opencharly/distro-fedora`** repo (git submodule at
> **`box/fedora`**), discovered as a `box/<name>/charly.yml` box. Its base
> stack (`fedora-nonfree` → `fedora`) is bare-local in the same self-contained
> submodule (`import: []`) — `base: fedora-nonfree`, which itself roots on the
> bare-local `fedora` base — and its 32 candies are pulled by github reference.
> Build/validate from
> the submodule: `charly -C box/fedora box build fedora-coder`, or
> `charly --repo opencharly/distro-fedora box build fedora-coder`. Deploy-mode verbs
> (`charly config`/`charly start`/`charly check box`) read the built image's OCI labels and
> work from anywhere once it's in local storage.

## Definition

```yaml
fedora-coder:
  base: fedora-nonfree            # = fedora + rpmfusion (for x264/ffmpeg-devel)
  ports:
    - "2222:2222"                 # sshd-wrapper
    - "18765:18765"               # charly-mcp (Streamable HTTP)
  candy:
    # Baseline (matches the charly-cachyos power-user pattern)
    - agent-forwarding
    - sshd
    - charly                          # the full toolchain: charly binary + virtualization + gocryptfs + socat
    - charly-mcp                      # MCP gateway for the entire charly CLI
    - container-nesting           # rootless nested podman/buildah/skopeo
    - dbus
    - tmux

    # Language runtimes + managers
    - language-runtimes           # Go + PHP + .NET 9 + nodejs-devel + python3-devel
    - golang
    - nodejs                       # generic nodejs candy (Node 22 on Fedora)
    - rust
    - pixi
    - uv                          # direct-download binary (no pixi env)

    # Build + developer tooling
    - build-toolchain
    - dev-tools                   # ripgrep, bat, fd, neovim, htop, …
    - pre-commit
    - direnv
    - gh                          # GitHub CLI + git + git-lfs (single-responsibility)
    - typst
    - asciinema

    # AI coding CLIs
    - claude-code
    - codex
    - gemini
    - forgecode                   # 5th CLI (astral-sh-style)
    - oracle

    # DevOps / cloud / infra
    - devops-tools                # AWS, Scaleway, kubectx/kubens, OpenTofu
    - kubernetes                  # kubectl, helm, k3d
    - docker-ce
    - github-actions              # act, actionlint
    - google-cloud
    - google-cloud-npm            # firebase + Gemini npm bindings
    - grafana-tools
```

Network: default `charly` bridge. The `port:` mapping is the right way to expose
sshd/charly-mcp, and bridge networking lets dev boxes coexist on one host via
normal `-p host:container` remapping (e.g. running `arch-coder` alongside
`fedora-coder` on the same machine).

No `uid:` / `gid:` / `user:` / `security:` override — inherits
`1000/1000/user` from `defaults` and the candy-level security from
`/charly-distros:container-nesting`. Rootless-first by design (shares this
posture with `/charly-openclaw:openclaw-desktop`).

## Resolved security posture (OCI label)

| Field | Value | Source |
|---|---|---|
| `cap_add` | **(empty)** | — |
| `security_opt` | `[unmask=/proc/*]` | `/charly-distros:container-nesting` |
| `devices` | `[/dev/fuse, /dev/net/tun]` | `/charly-distros:container-nesting` |
| `privileged` | `false` | — |
| Network | default `charly` bridge | charly.yml |
| UID / user | `1000 / user` | defaults |
| sudo | passwordless via `/etc/sudoers.d/charly-user` | `/charly-coder:sshd` |

**No `--privileged`. No `cap_add: ALL`. No `seccomp=unconfined`. No
`label=disable`.** All four power-user boxes (`fedora-coder`, `charly-fedora`,
`charly-arch`, `githubrunner`) run the rootless posture proven sufficient by the
`container-nesting` kernel RCA — see `/charly-distros:container-nesting` for the
`mount_too_revealing()` + `unmask=/proc/*` derivation.

## Network posture

Default `charly` bridge. Bridge networking plus normal `-p host:container`
remapping is the right pattern for dev boxes — it lets `fedora-coder` run
alongside `/charly-coder:arch-coder` on the same host (both want sshd on 2222 and
charly-mcp on 18765). To run two dev boxes side by side:

```bash
charly config arch-coder -p 2223:2222 -p 18766:18765     # alt-instance ports
charly config fedora-coder                               # canonical 2222/18765
```

Reaching host services from inside a bridge-networked container: use
the host's LAN IP or `host.containers.internal` (podman) rather than
`127.0.0.1`. For selkies-style sibling-container discovery, the charly.yml
`provides.env:` and `CHARLY_MCP_SERVERS` auto-injection give explicit hostnames.

## The 32-layer composition explained

**Why `fedora-nonfree` (not plain `fedora`)** — `build-toolchain` pulls
`x264-devel` + `ffmpeg-devel`, both of which live in RPM Fusion. Every
box that uses `build-toolchain` either bases on `fedora-nonfree` or
includes `rpmfusion` explicitly.

**Python story** — `python` (the pixi-python charly-layer) is NOT pulled in.
`supervisord`, `language-runtimes`, and `uv` all use system python3 from RPM,
not the conda-forge pixi env, so none of them declares `require: python`.
System Python is available via `language-runtimes` (`python3-devel` +
`python3-ramalama`). See the "Key Rules" note in the project rulebook (`AGENTS.md` / `CLAUDE.md`) ("don't declare
defensive deps").

**`uv` is a direct-download binary** (no pixi involvement). Lives at
`/usr/local/bin/uv` and `/usr/local/bin/uvx`, extracted from the
upstream astral-sh/uv tarball via the `download:` verb's
`strip_components: 1` modifier. See `/charly-coder:uv` and `/charly-image:layer`.

**`gh` owns all git tooling** — the `gh` candy installs `gh` + `git` +
`git-lfs` (with the noscripts + post-install trigger). `dev-tools`
intentionally does NOT install any of these. See `/charly-coder:gh`.

**No GPU by default** — `nvidia` / `cuda` intentionally NOT composed. If
you need CUDA in your dev box, spin a sibling `fedora-coder-nvidia`
with `base: nvidia` + the same candy list.

## Verification recipe (build + test + deploy-test)

```bash
# 1. Validate config (from the opencharly/distro-fedora submodule)
charly -C box/fedora box validate

# 2. Build (first time ≈ 15–30 min; cached rebuilds are fast thanks to
# LABEL-at-end ordering — test edits rebuild in seconds)
charly -C box/fedora box build fedora-coder

# 3. Build-scope tests (disposable container)
charly check box ghcr.io/opencharly/fedora-coder:latest
# target: 149 passed · 0 failed · 0 skipped

# 4. Deploy (no bind-mount needed; charly-mcp auto-falls back to opencharly/charly)
charly config fedora-coder
charly start fedora-coder

# 5. Full-scope tests — prefers the running container automatically
# (see /charly-check:check "Live vs disposable executor selection")
charly check box ghcr.io/opencharly/fedora-coder:latest
# target: 167 passed · 0 failed · 0 skipped

# 6. Clean up
charly stop fedora-coder
```

If you want `box.list.boxes` over the MCP surface to list YOUR
local checkout's boxes (rather than upstream opencharly/charly),
bind-mount the project:

```bash
charly config fedora-coder --bind project=/home/you/opencharly
charly start fedora-coder
```

The volume NAME is `project` (stable bind-mount API); the in-container
mount path is `/workspace`. See `/charly-coder:charly-mcp` for the three
deployment patterns (bind-mount / `CHARLY_PROJECT_REPO` / auto-fallback).

## Ports

| Port | Service | Bound by |
|---|---|---|
| 2222 | sshd-wrapper (SSH access as user with sudo) | `/charly-coder:sshd` |
| 18765 | charly-mcp (entire `charly` CLI as MCP tools, Streamable HTTP) | `/charly-coder:charly-mcp` |

Conflicts with `/charly-coder:charly-arch` (identical ports) and several
selkies-desktop variants on 2222. Use `-i <instance>` or `-p <remap>`
if running alongside.

## Test results

- `charly check box fedora-coder` — **149 passed · 0 failed · 0 skipped**.
- `charly check box fedora-coder` against a live running
  container — **167 passed · 0 failed · 0 skipped** (adds deploy-scope:
  sshd reachable, supervisord responding, dbus+charly-mcp+virtqemud+
  virtnetworkd services running, libvirt session list + KVM domcaps,
  mcp ping/list-tools/call-version/call-list-images via the charly-mcp
  auto-fallback).

## Image size

~14 GB uncompressed (kitchen-sink trade-off). Dominated by:

- `virtualization` — QEMU + libvirt (~800 MB)
- `docker-ce` — Docker engine + containerd + buildx + compose (~500 MB)
- 5 AI coding CLIs — `forgecode` alone is ~370 MB (native binary); the
  JS-only ones are smaller.
- `grafana-tools` — 7 binaries fetched from GitHub releases (~200 MB)
- `language-runtimes` — .NET 9 SDK is ~600 MB on its own.

To slim: drop the candy groups you don't need (AI CLIs, kubernetes,
google-cloud-npm) by forking charly.yml. See `/charly-image:image` for authoring.

## Key Candies

- `/charly-tools:charly` — the full toolchain: charly binary + virtualization + gocryptfs + socat (+ podman-machine, gvisor-tap-vsock for nested VMs)
- `/charly-coder:charly-mcp` — MCP gateway; auto-falls back to `opencharly/charly` when no bind-mount present
- `/charly-distros:container-nesting` — rootless nested podman recipe (authoritative RCA for `mount_too_revealing()` + `unmask=/proc/*`)
- `/charly-coder:sshd` — SSH daemon + passwordless sudo for the `user` account
- `/charly-coder:forgecode` — the 5th AI coding CLI
- `/charly-coder:language-runtimes` — Go + PHP + .NET + nodejs-devel + python3-devel (system-python stack, no pixi)
- `/charly-coder:uv` — direct-download binary at /usr/local/bin/uv
- `/charly-coder:gh` — GitHub CLI + git + git-lfs (single-responsibility)

## Cross-distro siblings

`fedora-coder` is one of **four cross-distro coder boxes** that share the identical 80-line `check:` block + ~30 identical candies; they diverge only in each candy's package-format section (`rpm:` / `pac:` / `deb:`) and a handful of distro-specific quirks handled inside individual candies.

| Box | Base | Package mgr | User model |
|---|---|---|---|
| `/charly-coder:fedora-coder` | `fedora-nonfree` (Fedora 43) | rpm | `user:user` (create) |
| `/charly-coder:arch-coder` | `arch` | pac + aur | `user:user` (create) |
| `/charly-coder:debian-coder` | `debian:13` | deb | `user:user` (create) |
| `/charly-coder:ubuntu-coder` | `ubuntu:24.04` | deb | `user:ubuntu` (**adopt** from base) |

All four produce the same daily-dev surface (sshd on 2222, charly-mcp on 18765, 5 AI CLIs, full language runtimes, DevOps tooling). Pick based on distro-family alignment with your team/CI. See `/charly-image:image` "user_policy" for the adopt-vs-create reconciliation that gives ubuntu-coder its `ubuntu` username.

## Related Boxes

- `/charly-openclaw:openclaw-desktop` — sibling rootless-first power-user box; same security posture + container-nesting, but adds the streaming desktop. Prefer when you want browser-accessible GUI + dev tools.
- `/charly-distros:charly-fedora` — minimal charly toolchain (no coding CLIs, no DevOps), also uid=1000 with sudo.
- `/charly-coder:charly-arch` — Arch Linux counterpart of charly-fedora.
- `/charly-distros:githubrunner` — self-hosted GitHub Actions runner; same uid=1000 posture.
- `/charly-hermes:hermes` — adds the Hermes AI agent daemon on top of the AI CLIs; prefer when you want an agent, not just CLI tools.

## Related Commands

- `/charly-core:shell` — open an interactive shell inside the container (as user, with sudo)
- `/charly-core:charly-config` — deploy setup (--bind project=…, tunnel, --update-all)
- `/charly-core:start`, `/charly-core:stop` — lifecycle
- `/charly-check:check` — live-service tests (`charly check live <name>`) and build-scope tests (`charly check box <ref>`)
- `/charly-build:charly-mcp-cmd` — MCP gateway documentation; `--no-default-repo` to disable auto-fallback
- `/charly-vm:vm` — nested libvirt VMs (via virtqemud inside the container)
- `/charly-image:layer` — authoring reference (covers the new `strip_components:` modifier)

## When to Use This Skill

**MUST be invoked** when the task involves:

- Building, deploying, or troubleshooting the `fedora-coder` box.
- Picking the right power-user base image for a coding/dev workload (this
  vs. `charly-fedora` vs. `charly-arch` vs. `openclaw-desktop`).
- Understanding the rootless-first architectural pattern shared by the
  four power-user boxes (kernel RCA belongs in
  `/charly-distros:container-nesting`; the composition that proves it works
  without a GUI is here).
- The full MCP auto-fallback deployment pattern when the `/workspace`
  bind-mount is intentionally left empty.

## Related

- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
