---
name: nvidia
description: |
  NVIDIA GPU base image with runtime support and CUDA toolkit on Fedora. Base for all
  GPU-accelerated boxes (python-ml, jupyter, ollama, comfyui).
  MUST be invoked before building, deploying, configuring, or troubleshooting the nvidia box.
---

# nvidia

NVIDIA GPU base image — provides GPU runtime (driver libs, CDI toolkit) and CUDA development toolkit on Fedora.

The `nvidia` and `cuda` candies are multi-distro (Fedora rpm + Arch pac), so a
CachyOS GPU base exists alongside this Fedora `nvidia` box: `cachyos.nvidia`
(cachyos + agent-forwarding + nvidia + cuda) in the `opencharly/distro-cachyos`
submodule. The two are siblings — pick the Fedora `nvidia` box for the
RPM-based GPU stack, `cachyos.nvidia` for the Arch/CachyOS GPU stack. See
`/charly-distros:cachyos`.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora-nonfree (fedora + RPM Fusion) |
| Layers | agent-forwarding, nvidia, cuda |
| Platforms | linux/amd64 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora-nonfree` (fedora + rpmfusion — provides RPM Fusion free + nonfree repos)
2. `nvidia` — GPU runtime: driver libs, nvidia-container-toolkit (CDI), VA-API
3. `cuda` — CUDA toolkit, cuDNN, onnxruntime, ffmpeg-libs

## Quick Start

The `nvidia` box lives in the `opencharly/distro-fedora` submodule (`box/fedora`):

```bash
charly -C box/fedora box build nvidia
charly shell nvidia
```

## Key Candies

- `/charly-distros:nvidia` — NVIDIA GPU runtime (driver libs, CDI generation via nvidia-ctk)
- `/charly-distros:cuda` — CUDA toolkit and GPU development libraries

## Derived Boxes

- `/charly-languages:python-ml` — ML Python environment
- `/charly-jupyter:jupyter` — Jupyter notebook server
- `/charly-ollama:ollama` — LLM inference server
- `/charly-comfyui:comfyui` — image generation UI

## Related Boxes

- `/charly-distros:fedora` — parent base (no GPU)
- `/charly-distros:cachyos` — `cachyos.nvidia` is the CachyOS GPU-base sibling (Arch/CachyOS GPU stack)
- `/charly-coder:charly-arch` — Arch Linux charly toolchain with nvidia (shared candies)
- `/charly-distros:charly-fedora` — Fedora charly toolchain with nvidia (shared candies)

## Verification

After `charly box build`:
- `charly shell nvidia -c "nvidia-smi"` — GPU info
- `charly shell nvidia -c "nvidia-ctk --version"` — CDI toolkit
- `charly shell nvidia -c "nvcc --version"` — CUDA compiler

## When to Use This Skill

**MUST be invoked** when the task involves the nvidia box, GPU base images, CUDA in containers, or CDI device configuration. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
