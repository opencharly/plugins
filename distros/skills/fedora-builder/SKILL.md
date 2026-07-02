---
name: fedora-builder
description: |
  Builder image with pixi, Node.js, and C/C++ build toolchain. Used as the
  default builder for multi-stage image builds.
  MUST be invoked before building, deploying, configuring, or troubleshooting the fedora-builder box.
---

# fedora-builder

Builder image with package managers and compilation tools. Default builder for pixi, npm, and cargo multi-stage builds (declared via `builds: [pixi, npm, cargo]`).

**Owned by the `opencharly/distro-fedora` submodule.** Lives bare-local in the
**`opencharly/distro-fedora`** submodule (mounted at `box/fedora`), alongside
`/charly-distros:fedora` + `/charly-distros:fedora-nonfree`; the submodule is
SELF-CONTAINED (`import: []`), so its images route builders to a bare-local
`fedora-builder`. Its `rpmfusion`/`pixi`/`nodejs`/`build-toolchain` candies are
pinned as github refs (`@github.com/opencharly/charly/candy/<name>:<tag>`) so
the same definition resolves in both main and the submodule. Build with
`charly box build fedora-builder` from the submodule.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Layers | rpmfusion, pixi, nodejs, build-toolchain |
| Platforms | linux/amd64 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` (quay.io/fedora/fedora:43)
2. `rpmfusion` — RPM Fusion free + nonfree repo configuration. Applied **first** so subsequent candies can `dnf install` packages from RPM Fusion (e.g. `x264-devel`, `ffmpeg-devel`, `libva-devel`)
3. `pixi` — pixi package manager + env paths
4. `nodejs` — Node.js + npm
5. `build-toolchain` — gcc, cmake, autoconf, ninja, git, pkg-config, **plus** the smithay/cargo build deps (`rust`, `cargo`, `clang-devel`, `nasm`, `wayland-devel`, `libva-devel`, `x264-devel`, `ffmpeg-devel`, `pixman-devel`, …) needed for builder-stage compilation of Wayland compositors like pixelflux. See `/charly-coder:build-toolchain` for the full grouped list.

## Why rpmfusion is first

The build-toolchain candy's `dnf install` references packages that live in RPM Fusion free
(`libva-devel`, `x264-devel`, `ffmpeg-devel`). These are required to build pixelflux from
source (its `libva-sys`, `x264-sys`, and `ffmpeg-sys-next` cargo crates link against the
system libs). Without rpmfusion applied first, those `dnf install` calls would fail.
See `/charly-selkies:selkies` (Patched pixelflux build pipeline) for the consumer story.

## Role in Build System

This image is referenced in `defaults.builders` as the builder for `pixi`, `npm`, and `cargo` multi-stage builds. It declares `builds: [pixi, npm, cargo]` to advertise its capabilities. The generator uses it as the `FROM` stage in multi-stage builds, providing build tools without bloating final images.

## Quick Start

```bash
charly box build fedora-builder
charly shell fedora-builder
```

## Key Candies

- `/charly-languages:pixi` — Python package management foundation
- `/charly-coder:nodejs` — Node.js runtime and npm
- `/charly-coder:build-toolchain` — C/C++ compilation tools

## Related Boxes

- `/charly-distros:fedora` — parent base

## Verification

After `charly box build`:
- `charly box list` — box appears in list
- `charly shell fedora-builder` — interactive shell works

## When to Use This Skill

**MUST be invoked** when the task involves the fedora-builder box, multi-stage builds, or build cache configuration. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
