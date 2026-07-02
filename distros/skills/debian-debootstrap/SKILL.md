---
name: debian-debootstrap
description: |
  Bootstrap-from-scratch Debian rootfs via debootstrap inside a privileged
  builder (from: builder:debootstrap, bootstrap_builder_image:
  debian-debootstrap-builder). Retained for offline/air-gapped builds and as a
  worked example of the from: builder:debootstrap pattern. Lives in the
  opencharly/distro-debian submodule (box/debian).
  MUST be invoked before building or troubleshooting debian-debootstrap.
---

# debian-debootstrap

Bootstrap-from-scratch Debian root filesystem, built via `debootstrap` inside
the privileged `/charly-distros:debian-debootstrap-builder` container
(`from: builder:debootstrap`, `bootstrap_builder_image: debian-debootstrap-builder`).

> **Lives in `opencharly/distro-debian`** (git submodule at `box/debian`). Build:
> `charly -C box/debian box build debian-debootstrap`.

## When to use it (and when not)

The canonical Debian base (`/charly-distros:debian`) pulls the upstream-published
`debian:13` OCI image from Docker Hub — that is the recommended, faster path
(no privileged build). This debootstrap variant exists for **offline /
air-gapped** builds and as a worked example of the `from: builder:debootstrap` +
`bootstrap_builder_image:` pattern (the deb-family counterpart of
`/charly-distros:arch-pacstrap` / `/charly-distros:cachyos-pacstrap`).

## Box Properties

| Property | Value |
|----------|-------|
| From | builder:debootstrap |
| bootstrap_builder_image | debian-debootstrap-builder |
| Distro | debian:13, debian |
| Build | deb |
| Home repo | opencharly/distro-debian (`box/debian`) |

The `debian` distro config (debootstrap suite `trixie`, mirror
`http://deb.debian.org/debian`, base packages, bootloader template) lives in the
embedded build vocabulary (`charly/charly.yml`, baked into the `charly` binary)
and is resolved by name from the submodule's `distro: debian` reference.

## Cross-References

- `/charly-distros:debian` — the recommended Docker-Hub base
- `/charly-distros:debian-debootstrap-builder` — the privileged builder it uses
- `/charly-vm:debian` — the VM built via the same debootstrap path

## When to Use This Skill

**MUST be invoked** before building or debugging the Debian debootstrap rootfs.
Invoke BEFORE reading source code or launching Explore agents.
