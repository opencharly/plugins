---
name: notebook-openrouter
description: |
  OpenRouter API integration notebook collection provisioned into the workspace volume at deploy time.
  3 Jupyter notebooks demonstrating OpenRouter API basics, model discovery, and practical inference.
  Data-only candy with env_require — first candy to use the env_require feature.
  Use when working with notebook-openrouter, OpenRouter API tutorials, or Jupyter+OpenRouter integration.
---

# notebook-openrouter -- OpenRouter API integration data candy

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | *(none)* |
| Packages | *(none)* |
| Services | *(none)* |
| Volumes | `workspace` -> `/workspace` (from jupyter) |
| Data | `data/openrouter` -> `workspace` volume, dest: `openrouter` |
| env_require | `OPENROUTER_API_KEY` — API key for OpenRouter LLM inference |
| Install files | *(none)* |

## How It Works

This is a **data candy** with an **env_require** declaration — it uses the `data:` field to map notebooks to a volume, and `env_require:` to declare that the `OPENROUTER_API_KEY` environment variable must be present:

```yaml
info: "OpenRouter API integration notebook collection"

env_require:
  - name: OPENROUTER_API_KEY
    description: "API key for OpenRouter LLM inference"

data:
  - src: data/openrouter
    volume: workspace
    dest: openrouter
```

At build time, the contents of `data/openrouter/` are staged into `/data/workspace/openrouter/` inside the box.

At deploy time, `charly config` copies the staged data into the workspace volume at `<workspace>/openrouter/`. The `dest: openrouter` field places the notebooks in a subdirectory rather than the volume root.

The `env_require` declaration is stored as an OCI label (`ai.opencharly.env_require`). At `charly config` time, if `OPENROUTER_API_KEY` is not present in the resolved environment, a warning is printed:
```
Warning: jupyter-ml-notebook requires OPENROUTER_API_KEY (API key for OpenRouter LLM inference) — not set
```

This is the first candy in the project to use the `env_require` feature.

## Included Notebooks

3 Jupyter notebooks covering OpenRouter API usage with the free model `qwen/qwen3.6-plus:free`:

| Notebook | Topic | Features |
|----------|-------|----------|
| `00_OpenRouter_Basics.ipynb` | API Basics | Authentication, simple chat completion, multi-turn conversation, error handling, usage/cost tracking |
| `01_OpenRouter_Models.ipynb` | Model Selection | List all models, filter free models, inspect model details (pricing, context, modality), compare responses across models |
| `02_OpenRouter_Inference.ipynb` | Practical Inference | Structured JSON output, text summarization, code generation (with exec), reasoning with thinking tokens, translation pipeline |

**Manifest:** `notebooks.yaml` — structured catalog with title, description, and ordering.

## Free Tier Rate Limit Gotcha

The free model `qwen/qwen3.6-plus:free` has strict rate limits (~1 request per minute). All notebooks include an `openrouter_chat()` / `chat()` retry helper that handles 429 responses with exponential backoff:

```python
def openrouter_chat(model, messages, retries=5, delay=15):
    for attempt in range(retries):
        response = requests.post(...)
        if response.status_code == 429:
            wait = delay * (attempt + 1)
            print(f"Rate limited, waiting {wait}s...")
            time.sleep(wait)
            continue
        response.raise_for_status()
        return response.json()
```

The retry helper also handles transient 502 upstream errors from Alibaba (the Qwen provider) where the response is 200 but missing the `choices` key.

## Providing the API Key

The `OPENROUTER_API_KEY` must be injected into the container environment:

```bash
# Via charly config (persisted in quadlet)
charly config jupyter-ml-notebook -e OPENROUTER_API_KEY=sk-or-v1-...

# Via workspace .env file
echo "OPENROUTER_API_KEY=sk-or-v1-..." >> ~/project/.env

# Via direnv .secrets (GPG-encrypted)
charly secrets gpg set OPENROUTER_API_KEY sk-or-v1-...
```

## Usage

```yaml
# charly.yml
jupyter-ml-notebook:
  candy:
    - jupyter-ml
    - notebook-templates
    - notebook-finetuning
    - notebook-ollama
    - notebook-llm-on-supercomputers
    - notebook-openrouter
    # ... other candies
```

```bash
# Deploy with API key
charly config jupyter-ml-notebook -e OPENROUTER_API_KEY=sk-or-v1-...
charly start jupyter-ml-notebook
# Open http://localhost:8888 -> navigate to openrouter/
```

## Used In Boxes

- `/charly-jupyter:jupyter-ml-notebook`

## Related Skills

- `/charly-image:layer` — data field documentation, env_require/env_accept field documentation
- `/charly-core:charly-config` — data provisioning and env_require warning during `charly config` setup
- `/charly-core:deploy` — volume backing configuration
- `/charly-jupyter:notebook-ollama` — sibling data candy pattern (Ollama integration notebooks)
- `/charly-jupyter:notebook-finetuning` — sibling data candy pattern (Unsloth fine-tuning notebooks)
- `/charly-jupyter:notebook-templates` — sibling data candy pattern (starter notebooks)
- `/charly-jupyter:notebook-llm-on-supercomputers` — sibling data candy pattern (TU Wien course notebooks)
- `/charly-jupyter:jupyter-ml-notebook` — the box that includes this candy

## When to Use This Skill

Use when the user asks about:

- The notebook-openrouter candy or its contents
- OpenRouter API tutorial notebooks or integration examples
- How to provide `OPENROUTER_API_KEY` to Jupyter containers
- The `env_require` feature (this is the first real consumer)
- Free tier rate limits on `qwen/qwen3.6-plus:free`
- Structured output, reasoning with thinking tokens, or model comparison via OpenRouter

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
