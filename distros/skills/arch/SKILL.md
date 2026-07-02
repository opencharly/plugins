---
name: arch
description: |
  Base Arch Linux image. Root of the box hierarchy for all pac-based boxes.
  MUST be invoked before building, deploying, configuring, or troubleshooting the arch box.
---

# arch

Root base image built from `quay.io/archlinux/archlinux`, pinned to a precise `base-*` date-serial tag in the arch base box (the `opencharly/distro-arch` submodule at `box/arch`; the quay mirror has the same content as `docker.io/library/archlinux` without Docker Hub's pull-rate limit). Foundation for all Arch Linux-based OpenCharly boxes.

## Box Properties

| Property | Value |
|----------|-------|
| Base | quay.io/archlinux/archlinux (pinned `base-*` tag in the `opencharly/distro-arch` submodule) |
| Layers | (none) |
| Platforms | linux/amd64 |
| Distro | arch |
| Build | pac |
| Builders | pixi, npm, cargo, aur → arch-builder |
| Registry | ghcr.io/opencharly |

## Quick Start

```bash
charly box build arch
charly shell arch
```

## Derived Boxes

`arch` (this base), `/charly-distros:arch-builder`, and the consumer Arch
boxes all live in the **`opencharly/distro-arch`** repo (git submodule at
**`box/arch`**), discovered as `box/<name>/charly.yml` boxes. That submodule
is SELF-CONTAINED (`import: []`): its base/builder stack is bare-local and it
composes the main repo's shared candies by `@github` git reference. Its boxes
write `base: arch` and route builders to `arch-builder` (bare-local refs, no
namespace qualifier):

- `/charly-distros:arch-builder` — adds pixi, nodejs, build-toolchain, yay (in `box/arch`)
- `/charly-coder:arch-coder` — kitchen-sink dev box (in `box/arch`)
- `/charly-coder:charly-arch` — full charly toolchain on Arch (in `box/arch`)
- `/charly-distros:arch-test` — pacman + AUR packaging test (in `box/arch`)

## Multi-Distro Support

This is the Arch counterpart to `/charly-distros:fedora`. The tag system (`distro: [arch]`, `build: [pac]`) selects `pac:` package sections and `pac:` tasks in tasks:. Candies shared between Arch and Fedora boxes use distro-specific sections:

```yaml
# charly.yml — multi-distro package declarations
rpm:
  packages: [neovim]     # Fedora
pac:
  packages: [neovim]     # Arch
```

AUR packages are authored under `distro.arch.aur.package` and built via
`arch-builder` (`yay`); the consuming box must add `aur` to its `build:` list
(`build: [pac, aur]`) — the base declares only `build: [pac]`. The
`/charly-distros:cachyos` base shares this exact AUR path (it routes `aur` →
`arch-builder` too), so AUR support is identical on `arch` and `cachyos`. See
`/charly-image:layer` "AUR (`aur:`)" for the authoring reference.

## Verification

After `charly box build`:
- `charly box list` — box appears in list
- `charly shell arch` — interactive shell works
- `charly shell arch -c "pacman --version"` — pacman available

## Related Boxes
- `/charly-distros:arch-builder` — adds pixi, nodejs, build-toolchain, yay
- `/charly-coder:charly-arch` — full charly toolchain on Arch
- `/charly-distros:arch-test` — pacman + AUR test image
- `/charly-distros:fedora` — RPM-based counterpart

## Related Commands
- `/charly-build:build` — build the arch base image
- `/charly-core:shell` — interactive shell in the base image

## When to Use This Skill

**MUST be invoked** when the task involves the arch base image or understanding the Arch box chain. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
