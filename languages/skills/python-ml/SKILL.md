---
name: python-ml
description: |
  GPU-accelerated Python ML environment with CUDA, PyTorch, and llama.cpp.
  No Jupyter server — use as a base for ML workloads or interactive shell.
  MUST be invoked before building, deploying, configuring, or troubleshooting the python-ml box.
---

# python-ml

GPU-accelerated Python environment with ML libraries — PyTorch, transformers, vLLM, llama.cpp.

## Box Properties

| Property | Value |
|----------|-------|
| Base | nvidia |
| Candies | agent-forwarding, python-ml |
| Platforms | linux/amd64 |
| Registry | ghcr.io/opencharly |

## Candy Composition

The `python-ml` candy is a **Tier 2 environment-owner meta-layer** that:
1. Owns the pixi.toml (core ML Python environment)
2. Composes `llama-cpp` (Tier 1 sub-candy) via `candy: [llama-cpp]`
3. Installs vLLM 0.19 wheel via a cmd task (after pixi env is established)

Build order: pixi environment → llama-cpp (binaries) → vLLM 0.19 wheel

## Full Candy Stack

1. `fedora` → `nvidia` (CUDA base)
2. `pixi` → `python` (transitive)
3. `python-ml` — ML pixi environment (Tier 2, owns pixi.toml)
4. `llama-cpp` — llama.cpp binaries (Tier 1, via `candy:` field)

## Quick Start

```bash
charly box build python-ml
charly shell python-ml
# python -c "import torch; print(torch.cuda.is_available())"
```

## Key Candies

- `/charly-languages:python-ml` — ML Python packages via pixi (Tier 2 meta-layer)
- `/charly-jupyter:llama-cpp` — llama.cpp binaries (sub-candy)
- `/charly-distros:cuda` — GPU support (via nvidia base)

## Related Boxes

- `/charly-distros:nvidia` — parent (GPU without ML packages)
- `/charly-jupyter:jupyter-ml` — adds JupyterLab + collaboration + MCP + unsloth on top of ML stack
- `/charly-jupyter:jupyter` — legacy Jupyter with ML stack (monolithic)
- `/charly-jupyter:unsloth-studio` — fine-tuning UI with similar ML stack

## Verification

After `charly box build`:
- `charly shell python-ml -c "python -c 'import torch; print(torch.cuda.is_available())'"` — CUDA OK
- `charly shell python-ml -c "python -c 'import vllm; print(vllm.__version__)'"` — vLLM OK
- `charly shell python-ml -c "ls ~/llama.cpp/llama-quantize"` — llama.cpp OK

## When to Use This Skill

**MUST be invoked** when the task involves the python-ml box, ML training environments, or GPU-accelerated Python. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
