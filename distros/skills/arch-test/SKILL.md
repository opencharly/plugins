---
name: arch-test
description: |
  Test box for Arch Linux pacman and AUR package installation.
  MUST be invoked before building or troubleshooting the arch-test box.
---

# arch-test

Test box that validates both `pac:` (pacman) and `aur:` (AUR) package formats on Arch Linux. Used to verify the multi-distro build system handles Arch packaging correctly.

`arch-test` lives in the **`opencharly/distro-arch`** repo (git submodule at
**`box/arch`**). The test candies `arch-pac-test` / `arch-aur-test` are vendored
locally in this repo's `candy/` (resolved via its `discover:` block); the `arch`
base + `arch-builder` are bare-local in the same self-contained submodule
(`import: []`) — `base: arch`. Build from
the submodule: `cd box/arch && charly box build arch-test`.

## Box Properties

| Property | Value |
|----------|-------|
| Base | arch |
| Build | pac, aur |
| Layers | agent-forwarding, arch-pac-test, arch-aur-test |
| Platforms | linux/amd64 |
| Registry | ghcr.io/opencharly |

## What It Tests

- **`pac:` format** (via arch-pac-test) — installs `neovim` and `ripgrep` from official Arch repos
- **`aur:` format** (via arch-aur-test) — installs `yay-bin` from the AUR using arch-builder

## Quick Start

```bash
charly box build arch-test
charly shell arch-test
```

## Verification

```bash
charly shell arch-test -c "nvim --version"     # pac: package installed
charly shell arch-test -c "rg --version"       # pac: package installed
charly shell arch-test -c "which yay"          # aur: package installed
```

## Related

- `/charly-distros:arch` — base image
- `/charly-distros:arch-builder` — builder image (provides yay for AUR builds)
- `/charly-distros:arch-pac-test` — pacman test candy
- `/charly-distros:arch-aur-test` — AUR test candy

## When to Use This Skill

**MUST be invoked** when the task involves building or troubleshooting the arch-test box, or validating Arch Linux package format support.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
