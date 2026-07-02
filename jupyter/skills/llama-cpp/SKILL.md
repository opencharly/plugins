---
name: llama-cpp
description: |
  llama.cpp prebuilt binaries and GGUF conversion tools.
  Use when working with llama.cpp, GGUF model conversion, or llama-quantize/llama-cli.
---

# llama-cpp -- llama.cpp prebuilt binaries and GGUF tools

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | None |
| Ports | — |
| Service | — |
| Install files | `charly.yml`, `task:` |

## What It Installs

Downloads the latest llama.cpp release from GitHub into `~/llama.cpp`:

**Binaries:** `llama-quantize`, `llama-cli`, shared libraries (`lib*.so*`)

**Python tools:** `convert_hf_to_gguf.py`, `gguf-py` package (from source tarball)

## Environment

| Variable | Value | Purpose |
|----------|-------|---------|
| `LLAMA_CPP_PATH` | `~/llama.cpp` | Location of llama.cpp binaries |
| `PATH` (appended) | `~/llama.cpp` | Makes llama-quantize/llama-cli available |

## Design: Tier 1 "Post-install" Layer

This candy has **no pixi.toml** and **no depends**. It downloads prebuilt binaries and sets environment variables. It is designed to be composed into environment-owning candies (Tier 2) via the `candy:` field.

The user-phase tasks run after the pixi environment is established by the parent candy. The `gguf` Python package (for programmatic GGUF access) is declared in the parent candy's pixi.toml, not here.

## Used In Candies

- `/charly-languages:python-ml` — via `candy: [llama-cpp]`
- `/charly-jupyter:jupyter-ml` — via `candy: [llama-cpp, unsloth]`
- `/charly-jupyter:unsloth-studio` — via `candy: [llama-cpp, unsloth]`

## Related Candies

- `/charly-jupyter:unsloth` — Fine-tuning (depends on llama.cpp for GGUF conversion)

## Used In Boxes

- `/charly-languages:python-ml` (via `python-ml` metalayer)
- `/charly-immich:immich-ml` (via `python-ml` metalayer)
- `/charly-jupyter:jupyter-ml` (via `jupyter-ml` metalayer)
- `/charly-jupyter:jupyter-ml-notebook` (via `jupyter-ml` metalayer)
- `/charly-jupyter:unsloth-studio` (via `unsloth-studio` metalayer)

## When to Use This Skill

Use when the user asks about:

- llama.cpp binaries inside containers
- GGUF model conversion (convert_hf_to_gguf.py)
- llama-quantize or llama-cli
- The `LLAMA_CPP_PATH` environment variable

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
