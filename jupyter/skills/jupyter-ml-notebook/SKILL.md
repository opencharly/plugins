---
name: jupyter-ml-notebook
description: |
  Full CUDA ML JupyterLab box with finetuning, Ollama, and LLM course notebooks, CRDT MCP server, and real-time collaboration.
  Base: nvidia. Port 8888. Combines jupyter-ml with 37 Unsloth fine-tuning notebooks, 6 Ollama integration notebooks, and 15 LLM course notebooks.
  MUST be invoked before building, deploying, or troubleshooting the jupyter-ml-notebook box.
---

# jupyter-ml-notebook -- GPU ML Jupyter with Fine-tuning Notebooks

## Box Definition

```yaml
jupyter-ml-notebook:
  base: nvidia
  candy:
    - agent-forwarding
    - jupyter-ml
    - notebook-templates
    - notebook-finetuning
    - notebook-ollama
    - notebook-llm-on-supercomputers
    - notebook-openrouter
    - dbus
    - charly
  ports:
    - "8888:8888"
  platforms:
    - linux/amd64
```

## What's Different from jupyter-ml

This box is identical to `jupyter-ml` with two data candy additions:
- `notebook-finetuning` — seeds 37 Unsloth fine-tuning notebooks into `/workspace/finetuning/`
- `notebook-ollama` — seeds 6 Ollama integration notebooks into `/workspace/ollama/`

The Ollama notebooks require a running `ollama` deployment. When deployed via `charly config ollama --update-all`, the `OLLAMA_HOST` env var is automatically injected via `env_provide` -- no manual configuration needed.

## Candy Composition

- `jupyter-ml` — Tier 2 environment-owning meta-layer (PyTorch >= 2.10.0, vLLM 0.19, unsloth, LangChain, CRDT MCP via jupyter-mcp sub-candy)
- `notebook-templates` — Starter notebooks (data candy, seeds /workspace)
- `notebook-finetuning` — 37 Unsloth fine-tuning notebooks (data candy, seeds /workspace/finetuning/)
- `notebook-ollama` — 6 Ollama integration notebooks (data candy, seeds /workspace/ollama/)
- `notebook-llm-on-supercomputers` — 15 LLM course notebooks (data candy, seeds /workspace/llms_on_supercomputers/)
- `agent-forwarding` — SSH/GPG agent forwarding
- `dbus` — D-Bus session bus
- `charly` — OpenCharly CLI

## Ports

| Port | Service |
|------|---------|
| 8888 | JupyterLab + MCP endpoint at `/mcp` |

## Volumes

| Name | Path | Purpose |
|------|------|---------|
| workspace | /workspace | Persistent notebook storage |
| models | ~/.cache/huggingface | HuggingFace model cache (from unsloth sub-candy) |

## Data Candies

| Candy | Target | Dest | Contents |
|-------|--------|------|----------|
| notebook-templates | workspace | *(root)* | getting-started.ipynb |
| notebook-finetuning | workspace | finetuning/ | 37 Unsloth notebooks (SFT, GRPO, DPO, RLOO, QLoRA) |
| notebook-ollama | workspace | ollama/ | 6 Ollama API notebooks (requests, OpenAI, ollama lib, GPU, HuggingFace, Anthropic) |
| notebook-llm-on-supercomputers | workspace | llms_on_supercomputers/ | 15 LLM course notebooks (prompt engineering, RAG, fine-tuning) + datasets |

## File Layout in JupyterLab

```
/workspace/
  getting-started.ipynb                    (from notebook-templates)
  finetuning/                               (from notebook-finetuning)
    .env.example
    notebooks.yaml
    00_Unsloth_Setup.ipynb
    01_FastInference_Llama.ipynb
    01_FastInference_Qwen.ipynb
    02_Vision_Training_Ministral.ipynb
    03_SFT_Training_Qwen.ipynb
    04_GRPO_Training_Qwen.ipynb
    05_DPO_Training_Qwen.ipynb
    06_Reward_Training_Qwen.ipynb
    07_RLOO_Training_Qwen.ipynb
    08_QLoRA_Alpha_Scaling_Ministral.ipynb
    ... (37 notebooks total)
  ollama/                                   (from notebook-ollama)
    notebooks.yaml
    00_Ollama_Requests.ipynb
    01_Ollama_GPU.ipynb
    02_Ollama_OpenAI.ipynb
    03_Ollama_Library.ipynb
    04_Ollama_HuggingFace.ipynb
    05_Ollama_Anthropic.ipynb
  llms_on_supercomputers/                   (from notebook-llm-on-supercomputers)
    notebooks.yaml
    datasets/
    D0_00_Bazzite_Setup.ipynb
    D1_01_Prompting_with_LangChain.ipynb
    D1_02_Prompt_templates_and_parsing.ipynb
    ... (15 notebooks total)
```

## Service Environment Integration

This box is a **consumer** of env_provide variables from infrastructure candies:

| Variable | Injected by | Value |
|----------|------------|-------|
| `OLLAMA_HOST` | `/charly-ollama:ollama` | `http://charly-ollama:11434` |

The notebooks read `OLLAMA_HOST` via `os.getenv("OLLAMA_HOST", "http://localhost:11434")`. When ollama is deployed via `charly config ollama --update-all`, the env_provide mechanism overrides the localhost default automatically.

## Quick Start

```bash
charly box build jupyter-ml-notebook
charly config jupyter-ml-notebook
charly start jupyter-ml-notebook
charly status jupyter-ml-notebook
charly logs jupyter-ml-notebook -f
# JupyterLab: http://localhost:8888
# MCP endpoint: http://localhost:8888/mcp

# With bind-backed workspace (data seeded into local dir):
charly config jupyter-ml-notebook --bind workspace=/path/to/project
```

## Notebook Workarounds

The notebook-finetuning include compatibility fixes for current library versions:
- **flex_attention disabled** in Ministral/Pixtral notebooks (transformers 5.5 bug)
- **max_memory={0: "14GB"}** for Pixtral-12B notebooks (accelerate device_map estimation fix)
- **packing=True** in all SFTConfig cells (TRL 1.0 requirement)
- **max_prompt_length removed** from DPO notebooks (deprecated in TRL 1.0)

## Verify

```bash
charly shell jupyter-ml-notebook -c "pixi run verify-pytorch"
charly shell jupyter-ml-notebook -c "pixi run verify-unsloth"
charly shell jupyter-ml-notebook -c "pixi run verify-mcp"
charly shell jupyter-ml-notebook -c "ls /workspace/finetuning/"
charly shell jupyter-ml-notebook -c "ls /workspace/ollama/"
charly shell jupyter-ml-notebook -c "ls /workspace/llms_on_supercomputers/"
```

## Related Boxes

- `/charly-jupyter:jupyter-ml` — Same stack without finetuning notebooks
- `/charly-jupyter:jupyter` — Lightweight variant (no CUDA, multi-arch)
- `/charly-jupyter:unsloth-studio` — Unsloth Studio UI (different pixi env, same finetuning notebooks)

**MCP testing:** same 3 deploy-scope `mcp:` checks as `jupyter-ml` are inherited here. See `/charly-build:charly-mcp-cmd` for the verb reference.

## When to Use This Skill

MUST be invoked before building, deploying, configuring, or troubleshooting the jupyter-ml-notebook box.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
