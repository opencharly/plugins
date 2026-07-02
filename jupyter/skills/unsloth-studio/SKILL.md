---
name: unsloth-studio
description: |
  Unsloth Studio fine-tuning web UI with CUDA GPU support, vLLM inference, and llama.cpp.
  Runs as a supervisord service on ports 8888 (Studio) and 8000 (vLLM API).
  MUST be invoked before building, deploying, configuring, or troubleshooting the unsloth-studio box.
---

# unsloth-studio

Unsloth Studio web UI for LLM fine-tuning with GPU acceleration.

## Box Properties

| Property | Value |
|----------|-------|
| Base | nvidia |
| Candies | agent-forwarding, unsloth-studio, notebook-finetuning, dbus, charly |
| Platforms | linux/amd64 |
| Ports | 8888, 8000 |
| Registry | ghcr.io/opencharly |

## Candy Composition

The `unsloth-studio` candy is a **Tier 2 environment-owner meta-layer** that:
1. Owns the pixi.toml (fine-tuning Python environment)
2. Composes two Tier 1 sub-candies via `candy: [llama-cpp, unsloth]`
3. Defines the supervisord service for the Studio web UI

Build order: pixi environment → llama-cpp (binaries) → unsloth (vLLM 0.19 wheel + unsloth pip + torch.compile patch) → supervisord config

## Full Candy Stack

1. `fedora` → `nvidia` (CUDA base)
2. `pixi` → `python` → `supervisord` (transitive)
3. `unsloth-studio` — Tier 2 meta-layer (owns pixi.toml, service config)
4. `llama-cpp` — llama.cpp binaries (Tier 1, via `candy:`)
5. `unsloth` — vLLM 0.19 + unsloth pip install + torch.compile patch (Tier 1, via `candy:`)

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 8888 | Unsloth Studio UI | HTTP |
| 8000 | vLLM API server | HTTP |

## Volumes

| Name | Path | Purpose |
|------|------|---------|
| models | ~/.cache/huggingface | HuggingFace model cache |
| workspace | /workspace | Training data and outputs |

## Quick Start

```bash
charly box build unsloth-studio
charly config unsloth-studio
charly start unsloth-studio
# Open http://localhost:8888
```

## Key Candies

- `/charly-jupyter:unsloth-studio` — Studio web UI service + pixi.toml (Tier 2)
- `/charly-jupyter:llama-cpp` — llama.cpp binaries (Tier 1 sub-candy)
- `/charly-jupyter:unsloth` — vLLM 0.19 + unsloth fine-tuning + torch.compile patch (Tier 1 sub-candy)
- `/charly-jupyter:notebook-finetuning` — 37 Unsloth fine-tuning notebooks provisioned into workspace volume
- `/charly-distros:nvidia` — GPU runtime and CDI device auto-detection (base)
- `/charly-distros:cuda` — CUDA toolkit and libraries (via nvidia base)
- `/charly-infrastructure:dbus-layer` — session bus for desktop notifications
- `/charly-tools:charly` — in-container `charly` CLI toolchain (scripting, service management)
- `/charly-distros:agent-forwarding` — SSH/GPG/direnv agent forwarding

## Related Boxes

- `/charly-distros:nvidia` — parent (GPU without Studio)
- `/charly-jupyter:jupyter-ml` — alternative ML UI with JupyterLab + CRDT MCP (same Tier 1 sub-candies)
- `/charly-languages:python-ml` — ML libraries without any UI
- `/charly-jupyter:jupyter` — legacy Jupyter with ML (shares port 8888)
- **CachyOS variant** — `cachyos.unsloth-studio` is the CachyOS GPU sibling (built on the `cachyos.nvidia` GPU base) in the `opencharly/distro-cachyos` submodule. See `/charly-distros:cachyos`.

## Verification

After `charly start`:
- `charly status unsloth-studio` — container running
- `charly service status unsloth-studio` — all services RUNNING
- `curl -s -o /dev/null -w '%{http_code}' http://localhost:8888` — Studio HTTP returns 200

## When to Use This Skill

**MUST be invoked** when the task involves the unsloth-studio box, LLM fine-tuning via web UI, or Unsloth Studio deployment. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
