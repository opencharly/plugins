---
name: python-ml-layer
description: |
  Core ML/AI Python environment with PyTorch, vLLM runtime deps, and CUDA support.
  Tier 2 environment-owner meta-layer that composes llama-cpp.
  Use when working with machine learning, PyTorch, HuggingFace, or GPU computing.
---

# python-ml -- Core ML Python environment (Tier 2 meta-layer)

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `cuda` |
| Sub-candies | `llama-cpp` |
| Install files | `charly.yml`, `pixi.toml`, `plan:` |

## Architecture: Tier 2 Environment-Owner Meta-Layer

This candy **owns the pixi.toml** for the core ML Python environment and composes the `llama-cpp` Tier 1 candy via `candy: [llama-cpp]`. Build order: pixi environment → llama-cpp (binaries) → python-ml user-phase tasks (vLLM wheel).

## Environment Variables

| Variable | Value |
|----------|-------|
| `NVIDIA_PYTHON_PROJECT` | `~/.pixi` |
| `LD_LIBRARY_PATH` | `/usr/lib64:$HOME/llama.cpp` |

Plus from `llama-cpp` sub-candy:

| Variable | Value |
|----------|-------|
| `LLAMA_CPP_PATH` | `~/llama.cpp` |
| PATH (appended) | `~/llama.cpp` |

## Packages (pixi.toml)

**PyPI:** PyTorch >= 2.10.0 (CUDA 13.0), xformers, transformers, accelerate, safetensors, numpy, scipy, einops, pillow, kornia, spandrel, torchsde, vLLM runtime deps (blake3, flashinfer, numba, ray, xgrammar, etc.), gguf, pydantic, aiohttp

## Post-pixi Installs (`plan:` run steps)

- **vLLM 0.19 cu130 nightly wheel** (`pip install --no-deps`)

## Used In Boxes

- `/charly-languages:python-ml`
- `/charly-immich:immich-ml`

## Related Candies

- `/charly-jupyter:llama-cpp` — Sub-candy: llama.cpp binaries (composed via `candy:`)
- `/charly-distros:cuda` — CUDA toolkit dependency
- `/charly-jupyter:jupyter-ml` — Full ML + Jupyter variant (superset of python-ml's pixi env)
- `/charly-jupyter:unsloth-studio` — Fine-tuning variant (similar pixi env + unsloth)

## When to Use This Skill

Use when the user asks about:

- Machine learning Python environment
- PyTorch, transformers, or vLLM setup
- CUDA Python integration
- The `python-ml` candy, its packages, or its meta-layer composition
- The two-tier candy architecture for ML candies

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
