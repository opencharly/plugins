---
name: debian-debootstrap-builder
description: |
  Privileged debootstrap builder image (base: debian:13) — ships the
  debootstrap toolchain used to bootstrap a Debian rootfs from scratch for
  debian-debootstrap and the debian-debootstrap VM. Lives in the
  opencharly/distro-debian submodule (box/debian).
  MUST be invoked before building or troubleshooting debian-debootstrap-builder.
---

# debian-debootstrap-builder

Privileged builder image that ships the **debootstrap** toolchain (the
`debootstrap-builder` candy). It is the `from: builder:debootstrap` /
`bootstrap_builder_image:` target for `/charly-distros:debian-debootstrap` and the
`/charly-vm:debian-debootstrap-vm` bootstrap VM.

> **Lives in `opencharly/distro-debian`** (git submodule at `box/debian`). Build:
> `charly -C box/debian box build debian-debootstrap-builder`.

## Box Properties

| Property | Value |
|----------|-------|
| Base | `debian:13` |
| Distro | debian:13, debian |
| Build | deb |
| Layer | `debootstrap-builder` (pulled by github reference from the main repo) |
| Home repo | opencharly/distro-debian (`box/debian`) |

The `debootstrap-builder` candy (debootstrap + arch-install-scripts equivalents,
grub, parted) **stays in the main repo** and is shared with
`/charly-distros:ubuntu-debootstrap-builder` — both pull it by github reference. The
`debian` distro config (debootstrap suite/mirror/base packages, bootloader
template) is part of the embedded `distro:` vocabulary, loaded automatically by
the unified loader.

## Cross-References

- `/charly-distros:debian` — the Docker-Hub-equivalent base (`base: debian:13`)
- `/charly-distros:debian-debootstrap` — the bootstrap-from-scratch rootfs it builds
- `/charly-vm:debian-debootstrap-vm` — the VM built via the same debootstrap path
- `/charly-distros:ubuntu-debootstrap-builder` — the Ubuntu sibling (also `base: debian:13`)

## When to Use This Skill

**MUST be invoked** before building or debugging the Debian debootstrap builder.
Invoke BEFORE reading source code or launching Explore agents.
