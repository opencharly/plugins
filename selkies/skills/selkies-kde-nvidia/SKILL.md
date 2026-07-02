---
name: selkies-kde-nvidia
description: |
  The NVIDIA-GPU build of the KDE Plasma Selkies streaming desktop — full Plasma
  nested in pixelflux with REAL NVENC (cuda-arch-builder-compiled). MUST be invoked
  before building, deploying, or troubleshooting the selkies-kde-nvidia box.
---

# Box: selkies-kde-nvidia

The **NVIDIA-GPU build of the KDE Plasma flavor** (`/charly-selkies:selkies-kde`) —
the same headless-pod KDE streaming desktop on the CachyOS GPU base
(`cachyos.nvidia`), with pixelflux's **real NVENC** encoder compiled in. It is the
KDE sibling of `/charly-selkies:selkies-labwc-nvidia` (labwc + NVENC); both use
`builder.pixi: arch.cuda-arch-builder` so the `selkies` candy's `build.sh` compiles
pixelflux's real `nvenc-sys` encoder (the stock `arch-builder` has no CUDA → an
NVENC stub).

Owned by the `opencharly/distro-cachyos` submodule (`box/cachyos`).

## Definition

```yaml
selkies-kde-nvidia:
  base: nvidia                            # the CachyOS GPU base (cachyos.nvidia)
  build: [pac, aur]
  builder: {pixi: arch.cuda-arch-builder}   # nvcc + ffnvcodec headers → real NVENC
  candy:
    - agent-forwarding
    - selkies-kde-desktop
    - dbus
    - charly
  port: ["3000:3000", "9222:9222", "9224:9224", "2222:2222"]
  platform: [linux/amd64]
```

## NVENC compile-proof (check-coverage)

The box carries a build-scope `check:` check `pixelflux-nvenc-compiled` that
greps the built pixelflux `.so` for `NvEncodeAPICreateInstance` (the NVENC SDK
entry point the `nvenc-sys` crate binds). The stub build patches `nvenc-sys` out
of pixelflux's Cargo.toml, so the symbol is absent → the check FAILS on a
non-NVENC build. This is the regression-proof for the box's NVENC functionality
(identical to `/charly-selkies:selkies-labwc-nvidia`).

## Ports / Encoder

Same ports as `/charly-selkies:selkies-kde` (3000/9222/9224/2222). Encoder: real NVENC
on the passed-through NVIDIA GPU (CDI `--device nvidia.com/gpu=all`); falls back to
x264 when the GPU is unavailable.

## Quick Start

```bash
charly -C box/cachyos box build selkies-kde-nvidia
charly check box selkies-kde-nvidia            # build-scope incl. pixelflux-nvenc-compiled
```

NVENC at runtime requires a passed-through NVIDIA GPU — proven on the
`check-selkies-kde-nvidia-vm` bed (a `requires_exclusive: [nvidia-gpu]` passthrough
VM that asserts real NVENC frame production; the preemption arbiter frees the GPU
from any running holder). See `/charly-internals:disposable` + `/charly-check:check`.

## Related Skills

- `/charly-selkies:selkies-kde` — the cpu/default sibling (shared definition + the KDE flavor framing).
- `/charly-selkies:selkies-labwc-nvidia` — the labwc + NVENC sibling (same cuda-arch-builder + NVENC-compile proof).
- `/charly-selkies:selkies-kde-desktop` — the KDE metalayer + the de-SDDM headless-Plasma design.
- `/charly-distros:cachyos` — the CachyOS GPU base (`cachyos.nvidia`) + submodule.
- `/charly-distros:nvidia`, `/charly-distros:cuda` — the GPU runtime + CUDA toolkit candies.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries with `base:`/`from:`, build/validate/inspect/list).
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems).
