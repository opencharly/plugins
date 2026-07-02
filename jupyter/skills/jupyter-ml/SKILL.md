---
name: jupyter-ml
description: |
  Full CUDA ML JupyterLab box with real-time collaboration and CRDT MCP server.
  Base: nvidia. Port 8888. GPU-accelerated ML training + collaborative notebooks.
  MUST be invoked before building, deploying, or troubleshooting the jupyter-ml box.
---

# jupyter-ml -- GPU ML Jupyter with CRDT MCP

## Box Definition

```yaml
jupyter-ml:
  base: nvidia
  candy:
    - agent-forwarding
    - jupyter-ml
    - notebook-templates
    - dbus
    - charly
  ports:
    - "8888:8888"
  platforms:
    - linux/amd64
```

## Candy Composition

The `jupyter-ml` candy is a Tier 2 environment-owning meta-layer that composes:
- `llama-cpp` — llama.cpp prebuilt binaries + GGUF tools
- `unsloth` — vLLM 0.19 cu130 inference engine + fine-tuning (unsloth + unsloth-zoo) + vLLM torch.compile patch
- `jupyter-mcp` — CRDT MCP extension (fastmcp + jupyter_mcp package)

Additional candies from the box:
- `agent-forwarding` — SSH/GPG agent forwarding
- `notebook-templates` — Starter notebooks (data candy, seeds /workspace)
- `dbus` — D-Bus session bus
- `charly` — OpenCharly CLI

## Base Chain

```
quay.io/fedora/fedora:43
└── fedora
    └── fedora-nonfree (RPM Fusion repos)
        └── nvidia (NVIDIA drivers + container toolkit)
            └── jupyter-ml
```

## Ports

| Port | Service |
|------|---------|
| 8888 | JupyterLab + MCP endpoint at `/mcp` |

## Volumes

| Name | Path | Purpose |
|------|------|---------|
| workspace | /workspace | Persistent notebook storage |
| models | ~/.cache/huggingface | HuggingFace model cache (from unsloth sub-candy) |

## Service Environment Integration

This box receives env_provide variables from infrastructure candies when they are deployed:

| Variable | Injected by | Value |
|----------|------------|-------|
| `OLLAMA_HOST` | `/charly-ollama:ollama` | `http://charly-ollama:11434` |
| `PGHOST` | `/charly-infrastructure:postgresql` | `charly-postgresql` |
| `PGPORT` | `/charly-infrastructure:postgresql` | `5432` |
| `REDIS_URL` | `/charly-infrastructure:redis` or `/charly-infrastructure:valkey` | `redis://charly-<image>:6379` |

These variables are injected automatically into the container environment at `charly config` time when the corresponding service is deployed. No manual `-e` flags needed.

## Key Capabilities

- **JupyterLab** with real-time collaboration (jupyter-collaboration, Y-CRDT)
- **CRDT MCP Server** at `/mcp` — 11 tools for programmatic notebook access (server manages CRDT rooms invisibly; see `/charly-jupyter:jupyter-mcp` for the auto-attach + canonicalization design)
- **PyTorch** >= 2.10.0 with CUDA 13.0
- **vLLM** 0.19 inference engine
- **Unsloth** fine-tuning (LoRA, QLoRA)
- **LangChain** RAG stack (chromadb, faiss-cpu)
- **Evaluation** tools (evidently, sacrebleu, rouge-score)
- **Notebook templates** seeded into /workspace

## Quick Start

```bash
charly box build jupyter-ml
charly config jupyter-ml
charly start jupyter-ml
charly status jupyter-ml
charly logs jupyter-ml -f
# JupyterLab: http://localhost:8888
# MCP endpoint: http://localhost:8888/mcp
```

## Verify

```bash
charly shell jupyter-ml -c "pixi run verify-pytorch"
charly shell jupyter-ml -c "pixi run verify-vllm"
charly shell jupyter-ml -c "pixi run verify-unsloth"
charly shell jupyter-ml -c "pixi run verify-mcp"
charly shell jupyter-ml -c "pixi run verify-collaboration"
```

## Comparison with Other Jupyter Images

| | jupyter | jupyter-ml |
|---|---|---|
| Base | fedora | nvidia |
| CUDA | No | Yes |
| Arch | amd64 + arm64 | amd64 |
| MCP | CRDT (11 tools) | CRDT (11 tools) |
| Collaboration | Yes | Yes |
| ML Stack | No | Full |
| Volume | workspace | workspace + models |
| Notebook dir | /workspace | /workspace |

## Related Boxes

- `/charly-jupyter:jupyter-ml-notebook` — Same stack with fine-tuning notebooks
- `/charly-jupyter:jupyter` — Lightweight variant (no CUDA, multi-arch)
- `/charly-languages:python-ml` — ML base without Jupyter
- **CachyOS variant** — `cachyos.jupyter-ml` is the CachyOS GPU sibling (built on the `cachyos.nvidia` GPU base) in the `opencharly/distro-cachyos` submodule. See `/charly-distros:cachyos`.

**MCP testing:** inherits 3 deploy-scope `mcp:` checks from the `jupyter-ml` candy (`ping`, `list-tools`, `call list_notebooks`). Run `charly check live jupyter-ml --filter mcp` to exercise them. See `/charly-build:charly-mcp-cmd`.

## When to Use This Skill

MUST be invoked before building, deploying, configuring, or troubleshooting the jupyter-ml box.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
