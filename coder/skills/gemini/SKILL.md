---
name: gemini
description: |
  Google Gemini CLI for AI coding assistance and search.
  Use when working with the gemini candy.
---

# gemini -- Google Gemini CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `package.json` |
| Depends | `nodejs` |

## Usage

```yaml
# box or candy charly.yml — composition is a child node, not a top-level list
my-box:
    candy:
        base: fedora
    my-box-candy:
        candy:
            - gemini
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` — required runtime dependency
- `/charly-coder:claude-code` — sibling AI CLI in openclaw-full and hermes-full
- `/charly-coder:codex` — sibling AI CLI in openclaw-full and hermes-full

## Related Commands
- `/charly-build:secrets` — provision Gemini API credentials for the CLI
- `/charly-core:shell` — run gemini interactively inside a container
- `/charly-build:build` — installs gemini during image build

## When to Use This Skill

Use when the user asks about:
- Google Gemini CLI in containers
- AI coding assistance tools
- The `gemini` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
