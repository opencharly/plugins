---
name: comfyui
description: |
  ComfyUI image generation server with CUDA GPU support.
  Runs as a supervisord service on port 8188 with persistent storage.
  MUST be invoked before building, deploying, configuring, or troubleshooting the comfyui box.
---

# comfyui

GPU-accelerated ComfyUI image generation server with node-based workflow UI.

## Box Properties

| Property | Value |
|----------|-------|
| Base | nvidia |
| Candies | agent-forwarding, comfyui, dbus, charly |
| Platforms | linux/amd64 |
| Ports | 8188 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` → `nvidia` (CUDA base)
2. `pixi` → `python` → `supervisord` (transitive)
3. `comfyui` — ComfyUI server, models/output volume

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 8188 | ComfyUI web UI | HTTP |

## Quick Start

```bash
charly box build comfyui
charly config comfyui
charly start comfyui
# Open http://localhost:8188
```

## Key Candies

- `/charly-comfyui:comfyui` — ComfyUI installation, supervisord service, volume
- `/charly-distros:nvidia` — GPU runtime and CDI device auto-detection (base)
- `/charly-distros:cuda` — CUDA toolkit and libraries (via nvidia base)
- `/charly-infrastructure:dbus-layer` — session bus for desktop notifications
- `/charly-tools:charly` — in-container `charly` CLI toolchain (scripting, service management)
- `/charly-distros:agent-forwarding` — SSH/GPG/direnv agent forwarding

## Related Boxes

- `/charly-distros:nvidia` — parent (GPU without ComfyUI)
- **CachyOS variant** — `cachyos.comfyui` is the CachyOS GPU sibling (built on the `cachyos.nvidia` GPU base) in the `opencharly/distro-cachyos` submodule. See `/charly-distros:cachyos`.

## Verification

After `charly start`:
- `charly status comfyui` — container running
- `charly service status comfyui` — all services RUNNING
- `curl -s -o /dev/null -w '%{http_code}' http://localhost:8188` — ComfyUI HTTP returns 200

## When to Use This Skill

**MUST be invoked** when the task involves the comfyui box, image generation, or ComfyUI workflows. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
