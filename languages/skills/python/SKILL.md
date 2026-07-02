---
name: python
description: |
  Python 3.13 runtime installed via pixi (conda-forge).
  Use when working with Python, pixi environments, or Python dependencies.
---

# python -- Python 3.13 via pixi

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `pixi` |
| Install files | `charly.yml`, `pixi.toml` |

## Packages

Pixi (conda-forge): `python >=3.13,<3.14`

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - python
```

## Used In Boxes

- Transitive dependency via `supervisord` in most service boxes (`openclaw`, `jupyter`, `ollama`, `comfyui`, `immich`, etc.)

## Related Candies

- `/charly-languages:pixi` -- required dependency (provides pixi binary)
- `/charly-languages:python-ml` -- ML-focused Python with CUDA support
- `/charly-coder:language-runtimes` -- depends on python

## When to Use This Skill

Use when the user asks about:

- Python runtime in containers
- Pixi-managed Python installation
- The `python` candy
- Why `pip install` and `conda install` are not used (pixi is the only Python package manager)

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
