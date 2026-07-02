---
name: nano-pdf
description: |
  nano-pdf CLI for PDF editing with natural language.
  Use when working with the nano-pdf candy.
---

# nano-pdf -- PDF editing CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `pixi.toml` |
| Depends | `python` |

## Usage

```yaml
# box charly.yml — name-first: compose the candy via a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - nano-pdf
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-languages:python` — required Python runtime dependency
- `/charly-openclaw:openclaw-full` — metalayer that includes nano-pdf
- `/charly-coder:uv` — sibling Python tooling in openclaw-full

## Related Commands
- `/charly-build:build` — installs nano-pdf via the pixi builder during image build
- `/charly-core:shell` — run nano-pdf interactively inside a container

## When to Use This Skill

Use when the user asks about:
- PDF editing with natural language
- nano-pdf CLI tools
- The `nano-pdf` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
