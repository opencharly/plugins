---
name: unsloth
description: |
  Unsloth LLM fine-tuning library with vLLM integration. Tier 1 post-install layer —
  no pixi.toml, requires pixi env from a parent candy (python-ml, jupyter-ml, unsloth-studio).
  Use when working with Unsloth, LLM fine-tuning, or vLLM wheel installation.
---

# unsloth -- LLM fine-tuning (Tier 1 post-install layer)

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | None (requires pixi env from parent) |
| Volumes | `models` -> `~/.cache/huggingface` |
| Aliases | `unsloth` -> `unsloth` |
| Install files | `charly.yml`, `task:` |

## Architecture: Tier 1 Post-Install Layer

This candy has **no pixi.toml** and **no depends**. It installs pip packages into the pixi environment established by a Tier 2 "environment-owner" parent candy. The user-phase tasks run AFTER the parent's pixi COPY in the final image build.

**Cannot be used standalone** — must be composed into an environment-owner candy via the `candy:` field.

## Environment Variables

| Variable | Value |
|----------|-------|
| `UNSLOTH_SKIP_LLAMA_CPP_INSTALL` | `1` |
| `HF_HOME` | `~/.cache/huggingface` |

## Post-pixi Installs (tasks:)

1. **vLLM cu130 nightly wheel** (`pip install --no-deps`) — installed here because vLLM wheel must run after pixi env exists
2. **unsloth + unsloth-zoo** (`pip install --no-deps`) — incompatible with transformers 5.x in pixi solve
3. **opentelemetry runtime deps** (`pip install`) — pixi resolver conflict prevents solving these via conda-forge
4. **vLLM torch.compile patch** (`patch_vllm_size_nodes.py`) — fixes `_decompose_size_nodes` bug where `getitem` users and `x.size(dim)` patterns crash during model compilation (upstream: vllm-project/vllm#38360)

## Used In Candies (via `candy:` field)

- `/charly-jupyter:jupyter-ml` — `candy: [llama-cpp, unsloth, jupyter-mcp]`
- `/charly-jupyter:unsloth-studio` — `candy: [llama-cpp, unsloth]`

## Related Candies

- `/charly-jupyter:llama-cpp` — llama.cpp binaries (often paired as sibling Tier 1 candy)
- `/charly-jupyter:unsloth-studio` — Studio web UI (Tier 2 parent, owns pixi.toml)
- `/charly-jupyter:jupyter-ml` — ML Jupyter with MCP (Tier 2 parent, owns pixi.toml)
- `/charly-languages:python-ml` — Core ML environment (Tier 2, uses vllm pip install in its own tasks: instead)

## Used In Boxes

- `/charly-jupyter:jupyter-ml` (via `jupyter-ml` metalayer)
- `/charly-jupyter:jupyter-ml-notebook` (via `jupyter-ml` metalayer)
- `/charly-jupyter:unsloth-studio` (via `unsloth-studio` metalayer)

## When to Use This Skill

Use when the user asks about:

- Unsloth fine-tuning setup or configuration
- LLM fine-tuning environments
- The unsloth Python library or unsloth-zoo
- vLLM wheel installation inside pixi environments
- HuggingFace model cache volume
- The `unsloth` host alias
- The two-tier layer architecture for ML layers

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
