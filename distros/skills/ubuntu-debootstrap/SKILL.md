---
name: ubuntu-debootstrap
description: |
  Bootstrap-from-scratch Ubuntu 24.04 rootfs via debootstrap inside a privileged
  builder (from: builder:debootstrap, bootstrap_builder_image:
  ubuntu-debootstrap-builder). Retained for offline/air-gapped builds. Lives in
  the opencharly/distro-ubuntu submodule (box/ubuntu).
  MUST be invoked before building or troubleshooting ubuntu-debootstrap.
---

# ubuntu-debootstrap

Bootstrap-from-scratch Ubuntu 24.04 (noble) root filesystem, built via
`debootstrap` inside the privileged `/charly-distros:ubuntu-debootstrap-builder`
container (`from: builder:debootstrap`,
`bootstrap_builder_image: ubuntu-debootstrap-builder`).

> **Lives in `opencharly/distro-ubuntu`** (git submodule at `box/ubuntu`). Build:
> `charly -C box/ubuntu box build ubuntu-debootstrap`.

## When to use it (and when not)

The canonical Ubuntu base (`/charly-distros:ubuntu`) pulls the upstream-published
`ubuntu:24.04` OCI image from Docker Hub — that is the recommended, faster path.
This debootstrap variant exists for **offline / air-gapped** builds and as a
worked example of the `from: builder:debootstrap` pattern.

## Box Properties

| Property | Value |
|----------|-------|
| From | builder:debootstrap |
| bootstrap_builder_image | ubuntu-debootstrap-builder |
| Distro | ubuntu:24.04, ubuntu, debian |
| Build | deb |
| Home repo | opencharly/distro-ubuntu (`box/ubuntu`) |

The `ubuntu` distro config (`inherits: debian`; debootstrap suite `noble`,
mirror `http://archive.ubuntu.com/ubuntu`, components `main,universe`) lives in
the embedded build vocabulary (`charly/charly.yml`, baked into the `charly`
binary). The embedded vocabulary carries BOTH the `ubuntu` and `debian` distro
configs, so the `inherits: debian` resolution needs no reference to
`opencharly/distro-debian`.

## Cross-References

- `/charly-distros:ubuntu` — the recommended Docker-Hub base
- `/charly-distros:ubuntu-debootstrap-builder` — the privileged builder it uses
- `/charly-vm:ubuntu` — the VM built via the same debootstrap path

## When to Use This Skill

**MUST be invoked** before building or debugging the Ubuntu debootstrap rootfs.
Invoke BEFORE reading source code or launching Explore agents.
