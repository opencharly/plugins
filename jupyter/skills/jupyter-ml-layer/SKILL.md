---
name: jupyter-ml-layer
description: |
  Full CUDA ML stack + JupyterLab with real-time collaboration and CRDT MCP server on port 8888.
  Use when working with GPU-accelerated Jupyter notebooks, ML training with collaboration,
  or the jupyter-ml candy.
---

# jupyter-ml -- Full ML + JupyterLab with CRDT MCP

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `cuda`, `supervisord` |
| Sub-candies | `llama-cpp`, `unsloth`, `jupyter-mcp` |
| Ports | 8888 |
| Service | `jupyter-ml` (supervisord) |
| Volume | `workspace` at `/workspace` |
| Install files | `charly.yml`, `pixi.toml`, `plan:` |

## Architecture: Environment-Owning Meta-Layer

This is a **Tier 2 "environment owner"** candy that:
1. Owns the pixi.toml with ALL Python dependencies (Jupyter + ML + vLLM runtime deps)
2. Composes three Tier 1 sub-candies via `candy: [llama-cpp, unsloth, jupyter-mcp]`
3. MCP extension installed by the `jupyter-mcp` sub-candy (not directly in this candy's `plan:`)

Build order: pixi environment → llama-cpp (binaries) → unsloth (vllm wheel + unsloth pip + patch) → jupyter-mcp (MCP extension)

## Key Packages

**conda-forge:** JupyterLab >= 4.4.0, jupyter-resource-usage, jupyterlab-git, jupyterlab-lsp, jupyterlab-spellchecker, tensorboard, wandb, matplotlib, seaborn, pandas, numpy, scikit-learn, scipy, polars, pyarrow, dask, duckdb, altair, papermill, marimo, mkdocs, black, pytest

**PyPI (ML Core):** PyTorch >= 2.10.0 (CUDA 13.0), xformers, transformers >= 5.0.0rc1, accelerate, einops, kornia, spandrel, torchsde

**PyPI (vLLM Runtime):** blake3, flashinfer-python, numba, ray, xgrammar, and 25+ more runtime deps

**PyPI (Fine-tuning):** peft, trl, bitsandbytes, deepspeed, liger-kernel

**PyPI (LangChain):** langchain, langchain-core, langchain-openai, langchain-community, langchain-classic, langchain-anthropic, langchain-huggingface, langchain-ollama, chromadb, faiss-cpu

**PyPI (Evaluation):** evidently (with llm extras), evaluate, sacrebleu, rouge-score, nltk, bertviz

**PyPI (APIs):** openai, anthropic, gradio, ollama (client)

**PyPI (Collaboration):** jupyter-collaboration >= 4.1.0

**RPM (Fedora):** git, gcc, gcc-c++

**PAC (Arch/CachyOS):** git, gcc (includes g++) — the candy is multi-distro

## Environment

| Variable | Value | Purpose |
|----------|-------|---------|
| `NVIDIA_PYTHON_PROJECT` | `~/.pixi` | NVIDIA driver → pixi env mapping |
| `LD_LIBRARY_PATH` | `/usr/lib64:$HOME/llama.cpp` | CUDA libs + llama.cpp shared libs |
| `LLAMA_CPP_PATH` | `~/llama.cpp` | (from llama-cpp sub-candy) |
| `UNSLOTH_SKIP_LLAMA_CPP_INSTALL` | `1` | (from unsloth sub-candy) |
| `HF_HOME` | `~/.cache/huggingface` | (from unsloth sub-candy) |

## MCP Server Extension

Same CRDT MCP server as `/charly-jupyter:jupyter` — 11 tools for programmatic notebook access (notebook_list/create/get/watch/list_users, cell_get/update/insert/delete/execute, room_list). Clients no longer manage CRDT rooms — every notebook_*/cell_* call auto-attaches. See `/charly-jupyter:jupyter-mcp` "Usage philosophy and caveats" for the design principles.

Endpoint: `http://localhost:8888/mcp` (Streamable HTTP, MCP spec 2025-11-25)

## Comparison

| | jupyter | jupyter-ml |
|---|---|---|
| Base dep | supervisord | cuda, supervisord |
| GPU | No | CUDA 13.0 |
| Platforms | amd64 + arm64 | amd64 only |
| MCP | CRDT (11 tools) | CRDT (11 tools) |
| ML stack | No | Full (PyTorch, vLLM 0.19, unsloth) |
| Volume | workspace | workspace |

## Used In Boxes

- `/charly-jupyter:jupyter-ml`
- `/charly-jupyter:jupyter-ml-notebook`

## Related Candies

- `/charly-jupyter:jupyter` — Lightweight variant (no CUDA, multi-arch)
- `/charly-jupyter:llama-cpp` — Sub-candy: llama.cpp binaries
- `/charly-jupyter:unsloth` — Sub-candy: vLLM wheel + fine-tuning + vLLM patch
- `/charly-jupyter:jupyter-mcp` — Sub-candy: CRDT MCP extension
- `/charly-jupyter:notebook-templates` — Starter notebooks (data candy, used alongside this candy in boxes)
- `/charly-hermes:hermes` — MCP consumer (auto-discovers via `CHARLY_MCP_SERVERS`; uses jupyter tools to read/edit/execute cells)
- `/charly-openwebui:openwebui` — MCP consumer (sets `CODE_EXECUTION_ENGINE=jupyter` when this server is discovered, routing Open WebUI code blocks to the Jupyter kernel)

## When to Use This Skill

Use when the user asks about:

- GPU-accelerated Jupyter with collaboration
- ML training notebooks with CRDT MCP
- The `jupyter-ml` candy
- Combining jupyter features with CUDA ML

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
