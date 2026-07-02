---
name: build-toolchain
description: |
  C/C++ build toolchain with gcc, cmake, autoconf, ninja, git, and pkg-config.
  Use when working with native compilation, build tools, or C/C++ development.
---

# build-toolchain -- C/C++ compilation toolchain

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |

## Environment Variables

| Variable | Value |
|----------|-------|
| `CCACHE_DISABLE` | `1` |

## Packages (41 total, grouped by purpose)

The package list is the **centralized place** to add system libraries that any builder
stage needs. Box-specific cargo deps live here when they're broadly useful; truly
box-specific deps stay in their box's own candy.

### 1. Generic C/C++ build tools (21)

`autoconf`, `automake`, `binutils`, `bison`, `ccache`, `cli11-devel`, `cmake`, `flex`,
`gcc`, `gcc-c++`, `gdb`, `git`, `glibc-devel`, `libtool`, `make`, `ninja-build`, `patch`,
`pkgconf`, `pkgconf-m4`, `pkgconf-pkg-config`, `redhat-rpm-config`, `rpm-build`, `rpm-sign`.

### 2. Rust toolchain (2)

`rust`, `cargo`. Used by `setuptools-rust` and any candy that compiles a Smithay-based
Wayland compositor from source. See `/charly-coder:rust` for the disambiguation between
this builder-stage Rust and the runtime `rust` candy.

### 3. Bindgen runtime + assembler (2)

`clang-devel` — provides `libclang.so`, required by bindgen-based crates such as
`x264-sys` and `ffmpeg-sys-next`. Without it, those crates panic in their `build.rs` at
`bindgen-0.72.1/lib.rs:616:27`.

`nasm` — assembler for SIMD-accelerated native deps. The `turbojpeg-sys` crate vendors
libjpeg-turbo, whose CMake build calls `enable_language(ASM_NASM)` and fails without
nasm with `No CMAKE_ASM_NASM_COMPILER could be found`.

### 4. Smithay backend dev headers (10)

`wayland-devel`, `libudev-devel`, `libxkbcommon-devel`, `mesa-libgbm-devel`,
`libseat-devel`, `libinput-devel`, `systemd-devel`, `libdrm-devel`, `pixman-devel`,
`libjpeg-turbo-devel`.

These satisfy smithay's default feature set when pixelflux_wayland builds against
`smithay = { rev = "ca932e04…" }` with features
`["backend_drm", "backend_egl", "backend_gbm", "backend_libinput", "backend_udev",
"renderer_gl", "renderer_pixman", "use_system_lib", "desktop", "wayland_frontend"]`.
Each `backend_*` and `renderer_*` feature pulls a pkg-config lookup against the matching
`-devel` package at link time.

### 5. Codec dev libs from RPM Fusion free (3)

`libva-devel`, `x264-devel`, `ffmpeg-devel`.

These live in **RPM Fusion free** (not in the base Fedora repos), which is why
`/charly-distros:fedora-builder` now includes `/charly-distros:rpmfusion` **before**
`build-toolchain` in its candy list. They are required for compiling pixelflux's
`libva-sys`, `x264-sys`, and `ffmpeg-sys-next` cargo crates against the system
codec libraries.

See `/charly-selkies:selkies` (Patched pixelflux build pipeline) for the consumer story —
the selkies candy's `build.sh` clones pixelflux from a pinned commit, applies four
inline source patches, and runs `pip install .` against this builder stage.

## Cross-distro coverage

`rpm:` (Fedora), `pac:` (Arch), `deb:` (Debian/Ubuntu) — full parity. The deb section maps Fedora's ~40 `-devel` packages to their Debian `-dev` equivalents (`libclang-dev`, `libavformat-dev`, `libdrm-dev`, `libinput-dev`, `libturbojpeg0-dev`, `libseat-dev`, `libva-dev`, `libwayland-dev`, `libxkbcommon-dev`, `libgbm-dev`, `libsystemd-dev`, `libpixman-1-dev`, `libx264-dev`, `libudev-dev` — plus `build-essential`). Drops on deb: `redhat-rpm-config`, `rpm-build`, `rpm-sign`, `pkgconf-m4` (RPM-specific); `cli11-devel` (header-only, cmake FetchContent).

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - build-toolchain
```

## Used In Boxes

- `/charly-distros:fedora-builder`
- `/charly-distros:arch-builder`

## Related Candies
- `/charly-languages:pixi` — Sibling in builder images for conda-forge package builds
- `/charly-coder:nodejs` — Sibling in builder images for npm package builds
- `/charly-tools:yay` — Pairs in arch-builder for AUR builds
- `/charly-coder:rust` — Disambiguates the builder-stage `rust`+`cargo` packages here from the runtime `rust` candy
- `/charly-distros:rpmfusion` — Must be applied **before** this candy in fedora-builder so codec dev libs (`x264-devel`, `ffmpeg-devel`) can install
- `/charly-selkies:selkies` — Primary consumer of all the new cargo/codec deps (Patched pixelflux build pipeline)

## Related Commands
- `/charly-build:build` — Multi-stage builders consume this candy for pixi/npm/cargo builds
- `/charly-build:generate` — See how builder stages are generated from this candy

## When to Use This Skill

Use when the user asks about:

- C/C++ compilation inside containers
- Build tools (cmake, make, ninja, autoconf)
- Compiler toolchain setup
- The `build-toolchain` candy or its packages

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
