---
name: dev-tools
description: |
  Developer tools including bat, ripgrep, neovim, direnv, fd-find, htop,
  podman-compose, and many more CLI utilities.
  Use when working with developer tooling, CLI utilities, or container dev environments.
---

# dev-tools -- Developer CLI utilities

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `plan:` |

## Packages

RPM (with `--setopt=tsflags=noscripts`): `android-tools`, `apptainer`, `apptainer-suid`, `arch-install-scripts`, `asciinema`, `bat`, `bcc`, `bpftop`, `bpftrace`, `bridge-utils`, `debootstrap`, `direnv`, `dislocker`, `ecryptfs-utils`, `fastfetch`, `fd-find`, `fdupes`, `fuse-devel`, `fuse-dislocker`, `fuse3-devel`, `html2text`, `htop`, `jdupes`, `mosh`, `neovim`, `podman-compose`, `podman-machine`, `podman-remote`, `podman-tui`, `qemu-kvm`, `qemu-user-binfmt`, `qemu-user-static`, `rclone`, `restic`, `ripgrep`, `ShellCheck`, `squashfuse`, `strace`, `sysstat`, `thefuck`, `yamllint`, `yq`, `zoxide`

### Cross-distro coverage

`rpm:` (Fedora), `pac:` (Arch), `deb:` (Debian + generic Ubuntu), with a `ubuntu:24.04:` tag-section override. Not every package is available everywhere; per-distro drops are documented inline in `charly.yml`.

**Packages dropped per distro** (non-exhaustive):

- Arch: `apptainer-suid`, `dislocker`, `ecryptfs-utils`, `fuse-dislocker`, `podman-machine`, `podman-remote`, `podman-tui` — not packaged.
- Debian: same drops as Arch, plus `arch-install-scripts` (obviously) and `apptainer` itself (only in bookworm-backports, skipped on trixie).
- Ubuntu 24.04: additionally drops `fastfetch` — package not in noble main. Handled by a `ubuntu:24.04:` tag section that re-lists the deb packages minus fastfetch.

### bat → batcat symlink (Debian/Ubuntu)

Both Debian and Ubuntu rename `bat` → `batcat` in their archives to avoid a namespace collision with a legacy `bacula` utility. The `bat` package installs only `/usr/bin/batcat`; nothing lives at `/usr/bin/bat`. To keep downstream scripts, docs, and declarative tests portable, the candy ships a distro-tolerant symlink plan step:

```yaml
# a child step node under the dev-tools candy entity
dev-tools-symlink-bat:
    run: symlink batcat to bat on Debian/Ubuntu
    command: |
        if [ -f /usr/bin/batcat ] && [ ! -e /usr/bin/bat ]; then
          ln -sf /usr/bin/batcat /usr/bin/bat
        fi
    run_as: root
```

No-op on Fedora/Arch (where `/usr/bin/bat` already exists from the distro package) — the guard short-circuits. Creates the symlink on Debian/Ubuntu. Idempotent across rebuilds.

### fastfetch test — `exclude_distros: [ubuntu:24.04]`

The `fastfetch-binary` test is declared with an `exclude_distros:` filter:

```yaml
# an id-named check step node under the dev-tools candy entity
fastfetch-binary:
    check: the fastfetch binary is installed (skipped on ubuntu:24.04)
    id: fastfetch-binary
    file: /usr/bin/fastfetch
    exists: true
    exclude_distros:
        - ubuntu:24.04
```

On images whose `ai.opencharly.platform.distro` OCI label includes `ubuntu:24.04`, the test runner skips this check with a reason — see `/charly-check:check` "`exclude_distros:` field". This was added because dropping fastfetch from the `ubuntu:24.04:` tag section is clean, but the baked test probe would otherwise false-fail.

### Git tooling lives in `/charly-coder:gh`

dev-tools does NOT install `gh`, `git`, or `git-lfs` — those belong
exclusively to `/charly-coder:gh`, the dedicated GitHub / git tooling candy.
That keeps ownership unambiguous (one candy installs and tests them). If
you want the git tooling, compose `/charly-coder:gh` alongside
`/charly-coder:dev-tools`.

## Usage

```yaml
# charly.yml — composition is a child node, not a top-level list
my-dev:
    candy:
        base: fedora
    my-dev-candy:
        candy:
            - dev-tools
```

## Used In Boxes

- (none currently enabled)

## Related Candies
- `/charly-coder:gh` — Sibling GitHub CLI commonly paired with dev-tools
- `/charly-coder:devops-tools` — Sibling DevOps cloud CLI bundle in bootc images
- `/charly-coder:build-toolchain` — Sibling C/C++ toolchain in bootc image stacks

## Related Boxes
- `/charly-coder:debian-coder`, `/charly-coder:ubuntu-coder` — canonical consumers of the bat→batcat symlink
- `/charly-coder:fedora-coder`, `/charly-coder:arch-coder` — consumers where the symlink plan step is a harmless no-op

## Related Commands
- `/charly-build:build` — Build boxes that ship the dev-tools package set
- `/charly-core:shell` — Interactive shell to use bat/ripgrep/neovim/etc.
- `/charly-check:check` — `exclude_distros:` field reference for the fastfetch-binary test
- `/charly-image:layer` — authoring reference for distro-tolerant `command:` plan steps and `exclude_distros:`

## When to Use This Skill

Use when the user asks about:

- Developer tools in containers
- CLI utilities (bat, ripgrep, fd-find, neovim, etc.)
- Podman tooling inside containers
- The `dev-tools` candy or its packages
