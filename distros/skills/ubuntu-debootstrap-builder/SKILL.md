---
name: ubuntu-debootstrap-builder
description: |
  Privileged debootstrap builder image (base: debian:13 — debootstrap is a
  Debian tool that bootstraps Ubuntu suites too) — ships the debootstrap
  toolchain for ubuntu-debootstrap and the ubuntu-debootstrap VM. Lives in the
  opencharly/distro-ubuntu submodule (box/ubuntu).
  MUST be invoked before building or troubleshooting ubuntu-debootstrap-builder.
---

# ubuntu-debootstrap-builder

Privileged builder image that ships the **debootstrap** toolchain (the
`debootstrap-builder` candy). It is the `from: builder:debootstrap` /
`bootstrap_builder_image:` target for `/charly-distros:ubuntu-debootstrap` and the
`/charly-vm:ubuntu-debootstrap-vm` bootstrap VM.

> **Lives in `opencharly/distro-ubuntu`** (git submodule at `box/ubuntu`). Build:
> `charly -C box/ubuntu box build ubuntu-debootstrap-builder`.

## Box Properties

| Property | Value |
|----------|-------|
| Base | `debian:13` (debootstrap is a Debian tool — it bootstraps Ubuntu suites from a Debian builder) |
| Distro | debian:13, debian |
| Build | deb |
| Layer | `debootstrap-builder` (pulled by github reference from the main repo) |
| Home repo | opencharly/distro-ubuntu (`box/ubuntu`) |

The `debootstrap-builder` candy **stays in the main repo** and is shared with
`/charly-distros:debian-debootstrap-builder` — both pull it by github reference. The
`ubuntu` distro config (`inherits: debian`; debootstrap suite `noble`, mirror
`http://archive.ubuntu.com/ubuntu`, base packages) lives in the main repo's
embedded `distro:` vocabulary (`charly/charly.yml`) and resolves automatically —
the submodule imports nothing (`import: []`).

## Cross-References

- `/charly-distros:ubuntu` — the Docker-Hub base (`base: ubuntu:24.04`)
- `/charly-distros:ubuntu-debootstrap` — the bootstrap-from-scratch rootfs it builds
- `/charly-vm:ubuntu-debootstrap-vm` — the VM built via the same debootstrap path
- `/charly-distros:debian-debootstrap-builder` — the Debian sibling (same `base: debian:13`)

## When to Use This Skill

**MUST be invoked** before building or debugging the Ubuntu debootstrap builder.
Invoke BEFORE reading source code or launching Explore agents.
