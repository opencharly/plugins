---
name: unsloth-studio-layer
description: |
  Unsloth Studio fine-tuning web UI on ports 8888/8000 with vLLM inference.
  Tier 2 environment-owner meta-layer composing llama-cpp + unsloth, owns pixi.toml.
  Use when working with Unsloth Studio, the fine-tuning web UI, or the unsloth-studio box.
---

# unsloth-studio -- Fine-tuning Studio (Tier 2 meta-layer)

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `cuda`, `supervisord` |
| Sub-candies | `llama-cpp`, `unsloth` |
| Ports | 8888 (Studio UI), 8000 (vLLM API) |
| Volumes | `workspace` -> `/workspace` |
| Service | `unsloth-studio` (supervisord) |
| Install files | `charly.yml`, `pixi.toml` |

## Architecture: Tier 2 Environment-Owner Meta-Layer

This candy **owns the pixi.toml** for the fine-tuning environment and composes two Tier 1 candies via `candy: [llama-cpp, unsloth]`. Build order: pixi environment → llama-cpp (binaries) → unsloth (vLLM wheel + unsloth pip + patch) → supervisord config.

## Environment Variables

| Variable | Value |
|----------|-------|
| `NVIDIA_PYTHON_PROJECT` | `~/.pixi` |
| `LD_LIBRARY_PATH` | `/usr/lib64:$HOME/llama.cpp` |

Plus from sub-candies: `LLAMA_CPP_PATH`, `UNSLOTH_SKIP_LLAMA_CPP_INSTALL`, `HF_HOME`

## Packages (pixi.toml)

Fine-tuning focused ML stack: PyTorch (CUDA 13.0), xformers, transformers, accelerate, vLLM runtime deps, HuggingFace (datasets, tokenizers, sentencepiece), fine-tuning (peft, trl, bitsandbytes, liger-kernel), GGUF tools

## Service

Runs `pixi run start-studio` which executes `unsloth studio -H 0.0.0.0 -p 8888`. The Studio launches its own vLLM API server on port 8000 for inference and synthetic data generation.

## Used In Boxes

- `/charly-jupyter:unsloth-studio`

## Related Candies

- `/charly-jupyter:llama-cpp` — Sub-candy: llama.cpp binaries
- `/charly-jupyter:unsloth` — Sub-candy: vLLM + unsloth pip install + patch
- `/charly-infrastructure:supervisord` — Process manager dependency
- `/charly-jupyter:jupyter-ml` — Alternative: ML Jupyter with MCP (same Tier 1 sub-candies)
- `/charly-languages:python-ml` — Alternative: core ML without UI

## When to Use This Skill

Use when the user asks about:

- Unsloth Studio web UI setup
- The unsloth-studio service or container
- Port 8888 or 8000 in the context of fine-tuning
- The two-tier layer architecture for ML layers
- Fine-tuning pixi environment ownership

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
