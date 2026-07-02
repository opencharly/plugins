---
name: ubuntu-coder
description: |
  Kitchen-sink development box on Ubuntu 24.04 noble: coding + AI-coding
  CLIs + DevOps tooling in one container. Ubuntu base, 30+ direct candies
  mirroring fedora-coder's stack. Runs as uid 1000 `ubuntu` — the upstream
  ubuntu:24.04 account, adopted verbatim via the embedded build
  vocabulary's base_user declaration. 142/0/1-skip tests pass.
  Use when working with the ubuntu-coder box — especially when the
  `${USER}` / `${HOME}` / sudoers differ from the other three coder boxes.
---

# ubuntu-coder

Ubuntu 24.04 noble counterpart of `/charly-coder:fedora-coder`. Same 80-line test block, same ~30 candies, same rootless posture — but **the resolved user is `ubuntu` (not `user`)** because the upstream `ubuntu:24.04` base image ships a pre-existing `ubuntu:ubuntu` account at uid 1000, and the embedded `distro.ubuntu` vocabulary declares `base_user:` to adopt it. Everything that touches the user account — `${HOME}`, npm prefix, pixi env, sudoers — derives from `resolved.User = "ubuntu"`.

> **Location:** lives in the **`opencharly/distro-ubuntu`** repo (git submodule at
> **`box/ubuntu`**) — a SEPARATE repo from `opencharly/distro-debian`. Its ~31
> candies are pulled by github reference from the main repo. Build/validate from
> the submodule: `charly -C box/ubuntu box build ubuntu-coder`, or
> `charly --repo opencharly/distro-ubuntu box build ubuntu-coder`. Deploy-mode verbs
> read the built image's OCI labels and work from anywhere once it's local.

## Definition

```yaml
ubuntu-coder:
  base: ubuntu
  ports:
    - "2222:2222"                 # sshd-wrapper
    - "18765:18765"               # charly-mcp (Streamable HTTP)
  candy:
    # Same stack as debian-coder — see that skill for the full list
    - agent-forwarding
    - sshd
    - charly
    - charly-mcp
    - container-nesting
    - dbus
    - tmux
    - language-runtimes
    - golang
    - nodejs
    - rust
    - pixi
    - uv
    - build-toolchain
    - dev-tools
    - pre-commit
    - direnv
    - gh
    - typst
    - asciinema
    - claude-code
    - codex
    - gemini
    - forgecode
    - oracle
    - devops-tools
    - kubernetes
    - docker-ce
    - github-actions
    - google-cloud
    - google-cloud-npm
    - grafana-tools
```

## User model — adopt mode

The embedded build vocabulary (`charly/charly.yml`) declares `distro.ubuntu.base_user`:

```yaml
base_user:
  name: ubuntu
  uid: 1000
  gid: 1000
  home: /home/ubuntu
```

`ubuntu-coder` doesn't set an explicit `user:` field, so `user_policy: auto` (the default) adopts the base_user. The generator emits no `useradd` — the bootstrap section is a one-line comment:

```
# User ubuntu (uid=1000) adopted from base image (declared in the embedded distro.base_user) — no useradd needed
WORKDIR /home/ubuntu
USER 1000
```

Resolved identity: `User=ubuntu, UID=1000, GID=1000, Home=/home/ubuntu`. The image's OCI labels carry these values (`ai.opencharly.user="ubuntu"`, `ai.opencharly.home="/home/ubuntu"`) so deploy-mode quadlets and `charly shell` find them without re-reading `charly.yml`.

**Why adopt over rename?** Ubuntu's cloud-init tooling, documentation, and `/etc/passwd` metadata all expect the user to be named `ubuntu`. Renaming fights the upstream contract. Adopting honors it. See `/charly-image:image` "user_policy" for the full rationale and the 3-value policy table.

## Live verification

```
$ charly shell ubuntu-coder -c 'id; /usr/bin/dotnet --version; sudo -l'
uid=1000(ubuntu) gid=1000(ubuntu) groups=1000(ubuntu),4(adm),20(dialout),24(cdrom),25(floppy),27(sudo),29(audio),30(dip),44(video),46(plugdev),105(libvirt)
9.0.313
User ubuntu may run the following commands on <host>:
    (ALL : ALL) ALL
```

## Security posture

Identical to `/charly-coder:debian-coder` — the only diff is `User` field.

| Field | Value | Source |
|---|---|---|
| `cap_add` | **(empty)** | — |
| `security_opt` | `[unmask=/proc/*]` | `/charly-distros:container-nesting` |
| `devices` | `[/dev/fuse, /dev/net/tun]` | `/charly-distros:container-nesting` |
| `privileged` | `false` | — |
| Network | bridge | defaults |
| UID / user | `1000 / ubuntu` | **adopt mode** |
| sudo | passwordless via `/etc/sudoers.d/charly-user` (discovered via `getent passwd 1000` → `ubuntu`) | `/charly-coder:sshd` |

## Ubuntu-specific layer quirks (differences vs debian-coder)

- **fastfetch test is skipped** via `exclude_distros: [ubuntu:24.04]` (`/charly-coder:dev-tools`). Ubuntu 24.04 noble main does not ship `fastfetch` (Debian 13 trixie does, and so do Fedora/Arch). Skipping is cleaner than failing — see `/charly-check:check` for the `exclude_distros:` field of the declarative-test schema.
- **dotnet-sdk-9.0 source**: uses Microsoft's `dotnet-install.sh` (same as debian-coder). Note: Canonical's noble main/universe ships `dotnet-sdk-8.0` and `dotnet-sdk-10.0` but NOT 9.0; Microsoft's noble apt repo ships 10.0 only. `dotnet-install.sh --channel 9.0` is the only cross-distro-consistent path to .NET 9. See `/charly-coder:language-runtimes`.
- **Everything else** is identical to debian-coder. The sudoers `getent` discovery, bat→batcat symlink, virtualization package-existence tests — all are implemented once in the respective candies and work uniformly on both debian-coder and ubuntu-coder.

## Test results

`charly check box ghcr.io/opencharly/ubuntu-coder:latest` — **142 passed · 0 failed · 1 skipped** (fastfetch, by design).

## Verification recipe

```bash
# 1. Validate
charly -C box/ubuntu box validate

# 2. Build (auto-chains: ubuntu → ubuntu-builder → ubuntu-coder)
charly -C box/ubuntu box build ubuntu-coder

# 3. Disposable-container tests
charly check box ghcr.io/opencharly/ubuntu-coder:latest

# 4. Confirm adopt mode at runtime
charly shell ubuntu-coder -c "id"
# → uid=1000(ubuntu) gid=1000(ubuntu) ...

# 5. Deploy + live tests
charly config ubuntu-coder
charly start ubuntu-coder
charly check box ghcr.io/opencharly/ubuntu-coder:latest
```

## Gotcha: Dockerhub rate-limits during base pulls

Rebuilding the `ubuntu` base image pulls from `docker.io/library/ubuntu:24.04`. Unauthenticated Dockerhub pulls are rate-limited (100/6h per IP). If the build fails with `toomanyrequests`, the cleanest workaround is to pull from a non-Dockerhub mirror and retag:

```bash
podman pull public.ecr.aws/docker/library/ubuntu:24.04
podman tag public.ecr.aws/docker/library/ubuntu:24.04 docker.io/library/ubuntu:24.04
charly box build ubuntu-coder
```

AWS ECR Public mirrors the Dockerhub library namespace without rate-limiting unauthenticated pulls.

## Ports

| Port | Service | Bound by |
|---|---|---|
| 2222 | sshd-wrapper (SSH as `ubuntu` with sudo) | `/charly-coder:sshd` |
| 18765 | charly-mcp | `/charly-coder:charly-mcp` |

Conflicts with the other three coder-family boxes on these ports.

## Image size

~10.2 GB uncompressed, nearly identical to `/charly-coder:debian-coder`.

## Cross-distro siblings

- `/charly-coder:fedora-coder` — RPM-family, `user:user` create.
- `/charly-coder:arch-coder` — pacman-family + AUR, `user:user` create.
- `/charly-coder:debian-coder` — deb on Debian 13, `user:user` create.
- `/charly-coder:ubuntu-coder` — this box; deb on Ubuntu 24.04, `user:ubuntu` **adopt**.

## Related boxes

- `/charly-distros:ubuntu` — parent base; declares `base_user:` in the embedded build vocabulary.
- `/charly-distros:ubuntu-builder` — multi-stage builder, also runs as `ubuntu:1000`.

## Related layers

- `/charly-coder:sshd` — getent-based sudoers (works regardless of whether the uid-1000 account is `user` or `ubuntu`).
- `/charly-coder:dev-tools` — bat→batcat + fastfetch `exclude_distros`.
- `/charly-coder:language-runtimes` — Microsoft `dotnet-install.sh` for .NET 9.
- `/charly-infrastructure:virtualization` — `package:` + `package_map:` tests.
- `/charly-distros:container-nesting`, `/charly-tools:charly`, `/charly-coder:charly-mcp` — shared rootless baseline.

## Related commands

- `/charly-image:image` — **`user_policy:` field** (the pivot for this box's behavior).
- `/charly-build:build` — **`base_user:` declaration** (where `ubuntu:1000` is declared).
- `/charly-check:check` — `exclude_distros:` field reference.
- `/charly-build:generate` — adopt-vs-create writeBootstrap emission.
- `/charly-core:shell`, `/charly-core:charly-config`, `/charly-core:start`, `/charly-core:stop`.

## When to use this skill

**MUST be invoked** when:

- Building, deploying, or troubleshooting `ubuntu-coder`.
- Debugging any behavior that depends on `${USER}` or `${HOME}` inside an Ubuntu container (they resolve to `ubuntu` / `/home/ubuntu`, not `user` / `/home/user`).
- Writing a candy whose content references the uid-1000 account by name — it must not hardcode `user`; use `getent passwd 1000` or `${USER}` substitution in task fields where the generator expands it.
- Understanding Dockerhub rate-limit workarounds during base-image rebuilds.
