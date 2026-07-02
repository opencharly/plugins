---
name: cachyos-pacstrap
description: |
  Bootstrap-from-scratch CachyOS rootfs via pacstrap inside a privileged builder.
  Builds end-to-end as of charly 2026.141.1850 (shared pacstrap renderer emits
  Architecture + SigLevel); retained for offline/air-gapped builds. Lives in the
  opencharly/distro-cachyos submodule (box/cachyos).
  MUST be invoked before building or troubleshooting cachyos-pacstrap.
---

# cachyos-pacstrap

Bootstrap-from-scratch CachyOS root filesystem, built via `pacstrap` inside the
privileged `/charly-distros:cachyos-pacstrap-builder` container
(`from: builder:pacstrap`, `bootstrap_builder_image: cachyos-pacstrap-builder`).

> **Lives in `opencharly/distro-cachyos`** (git submodule at `box/cachyos`). Build:
> `charly -C box/cachyos box build cachyos-pacstrap`.

## When to use it (and when not)

The canonical CachyOS base (`/charly-distros:cachyos`) pulls the upstream-published
OCI image from Docker Hub — that is the recommended path and the one the CachyOS
project itself uses. This pacstrap variant exists for **offline / air-gapped**
builds and as a worked example of the `from: builder:pacstrap` +
`bootstrap_builder_image:` pattern.

## pacstrap x86_64_v3 + SigLevel (fixed)

Earlier this path was unusable: the privileged pacstrap step rejected the
CachyOS `x86_64_v3` packages (`package architecture is not valid`) and, on the
VM path, tripped GPGME signature checks (`GPGME error: No data`). **Fixed as of
charly 2026.141.1850** by the shared `renderPacstrapExtraConf` helper (`charly/build.go`,
used by both `runPrivilegedBootstrap` and `charly/vm_bootstrap.go`):

1. it derives an `[options] Architecture = x86_64 x86_64_v3` directive from the
   cachyos-v3 repos' microarch token, so pacman accepts `linux-cachyos` etc.;
2. it emits each repo's `SigLevel` — the VM bootstrap path previously open-coded
   the loop and dropped `SigLevel`, so `SigLevel = Never` cachyos repos fell
   back to signature-required and GPGME failed. Both paths now share one renderer
   (R3), so they can't diverge again.

Verified live: `charly -C box/cachyos box build cachyos-pacstrap` produces a
rootfs with `linux-cachyos` (`%ARCH% = x86_64_v3`) installed. (Requires an `charly`
with this fix — newer than the published release.) The Docker-Hub `/charly-distros:cachyos`
base is still the faster default (no privileged build).

## Box Properties

| Property | Value |
|----------|-------|
| From | builder:pacstrap |
| bootstrap_builder_image | cachyos-pacstrap-builder |
| Distro | cachyos, arch |
| Build | pac |
| Home repo | opencharly/distro-cachyos (`box/cachyos`) |

The `cachyos` distro config (pacstrap base packages, CachyOS keyring
`F3B607488DB35A47`, mirrorlist, `cachyos*` repos) lives in the embedded build
vocabulary (`charly/charly.yml`, baked into the `charly` binary) and is resolved
by name whenever a box declares `distro: cachyos`.

## Cross-References

- `/charly-distros:cachyos` — the recommended Docker-Hub base
- `/charly-distros:cachyos-pacstrap-builder` — the privileged builder it uses
- `/charly-vm:cachyos` — the VM built via the same pacstrap path

## When to Use This Skill

**MUST be invoked** before building or debugging the CachyOS pacstrap rootfs.
Invoke BEFORE reading source code or launching Explore agents.
