---
name: notebook-ollama
description: |
  Ollama integration notebook collection provisioned into the workspace volume at deploy time.
  6 Jupyter notebooks demonstrating Ollama via requests, OpenAI, ollama lib, Anthropic, HuggingFace, and GPU.
  Data-only candy — no packages, no services, no dependencies.
  Use when working with notebook-ollama, Ollama API tutorials, or Jupyter+Ollama integration.
---

# notebook-ollama -- Ollama integration notebook data candy

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | *(none)* |
| Packages | *(none)* |
| Services | *(none)* |
| Volumes | `workspace` -> `/workspace` (from jupyter) |
| Data | `data/ollama` -> `workspace` volume, dest: `ollama` |
| Install files | *(none)* |

## How It Works

This is a **data candy** — it uses the `data:` field in `charly.yml` to map a directory of notebooks to a named volume with a subdirectory destination:

```yaml
info: "Ollama integration notebook collection"

data:
  - src: data/ollama
    volume: workspace
    dest: ollama
```

At build time, the contents of `data/ollama/` are staged into `/data/workspace/ollama/` inside the box.

At deploy time, `charly config` or `charly update` copies the staged data into the workspace volume at `<workspace>/ollama/`. The `dest: ollama` field places the notebooks in a subdirectory rather than the volume root.

## Included Notebooks

6 Jupyter notebooks covering different Ollama client libraries:

| Notebook | Library | Features |
|----------|---------|----------|
| `00_Ollama_Requests.ipynb` | `requests` | Raw REST API: list, show, generate, chat, stream, embed, copy, delete |
| `01_Ollama_GPU.ipynb` | `requests` | GPU verification: nvidia-smi, inference metrics, VRAM monitoring |
| `02_Ollama_OpenAI.ipynb` | `openai` | OpenAI-compatible API: completions, chat, multi-turn, stream, embed |
| `03_Ollama_Library.ipynb` | `ollama` | Native Python library: all API operations + model management |
| `04_Ollama_HuggingFace.ipynb` | `ollama` | HuggingFace GGUF model import, verification, inference |
| `05_Ollama_Anthropic.ipynb` | `anthropic` | Anthropic-compatible API: chat, system prompts, streaming, tool calling, vision |

**Manifest:** `notebooks.yaml` — structured catalog with title, description, and ordering.

## Network Connectivity

The notebooks default to `http://localhost:11434` for the Ollama API endpoint. Each notebook reads:

```python
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
```

When the `ollama` box is deployed via `charly config ollama`, its `env_provide` automatically injects `OLLAMA_HOST=http://charly-ollama:11434` into the global `charly.yml` env. Any container configured after ollama (or reconfigured with `--update-all`) automatically gets the correct Ollama endpoint — no manual environment setup needed.

**Setup:**
```bash
charly config ollama --update-all    # deploys ollama + propagates OLLAMA_HOST to all
charly start ollama
charly start jupyter-ml-notebook   # OLLAMA_HOST already set via env_provide
```

Both containers must be on the same `charly` Podman network for DNS resolution to work.

See `/charly-core:charly-config` for `--update-all` and `/charly-ollama:ollama` for env_provide details.

## Notebook Compatibility Notes

### ollama Python library env var gotcha

The `ollama` Python library creates its HTTP client at import time by reading `OLLAMA_HOST` from `os.environ`. Module-level functions (`ollama.list()`, `ollama.generate()`, etc.) are **bound methods** on this cached client. Simply setting a Python variable doesn't propagate to the library.

The notebooks use this pattern to handle both fresh kernels and re-runs:

```python
import os
OLLAMA_HOST = os.getenv("OLLAMA_HOST", "http://localhost:11434")
os.environ["OLLAMA_HOST"] = OLLAMA_HOST

import ollama
import importlib; importlib.reload(ollama)  # Rebinds module functions
```

### Pydantic model changes (ollama >= 0.4)

The newer `ollama` library returns Pydantic models, not dicts. Model names are accessed via `.model` attribute (not `["name"]`), and the list is `.models` (not `.get("models", [])`):

```python
# Old (dict access)
model_names = [m.get("model", "") for m in models.get("models", [])]

# New (Pydantic attribute access)
model_names = [m.model for m in models.models]
```

### Default models

- 5 notebooks use `llama3.2:latest` (3.2B, Q4_K_M)
- `ollama_anthropic.ipynb` uses `ministral-3:3b-instruct-2512-q4_K_M`

Pull models before running: `charly shell ollama -c "ollama pull llama3.2"`

## Usage

```yaml
# charly.yml
jupyter-ml-notebook:
  candy:
    - jupyter-ml
    - notebook-templates
    - notebook-finetuning
    - notebook-ollama
    # ... other candies
```

```bash
# Deploy and start both services
charly config ollama && charly start ollama
charly config jupyter-ml-notebook && charly start jupyter-ml-notebook

# Pull a model, then open notebooks
charly shell ollama -c "ollama pull llama3.2"
# Open http://localhost:8888 -> navigate to ollama/
```

## Used In Boxes

- `/charly-jupyter:jupyter-ml-notebook`

## Related Skills

- `/charly-image:layer` — data field documentation and candy authoring rules
- `/charly-core:charly-config` — data provisioning during `charly config` setup
- `/charly-core:deploy` — volume backing configuration
- `/charly-jupyter:notebook-finetuning` — sibling data candy pattern (Unsloth fine-tuning notebooks)
- `/charly-jupyter:notebook-templates` — sibling data candy pattern (starter notebooks)
- `/charly-ollama:ollama` — the Ollama binary candy (server side)
- `/charly-ollama:ollama` — the standalone Ollama box (must be running for notebooks to connect)
- `/charly-jupyter:jupyter-ml-notebook` — the box that includes this candy

## When to Use This Skill

Use when the user asks about:

- The notebook-ollama candy or its contents
- Ollama API tutorial notebooks or integration examples
- How Jupyter notebooks connect to a separate Ollama container
- The `ollama` Python library env var or Pydantic API gotchas
- Which client libraries and API features are covered

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
