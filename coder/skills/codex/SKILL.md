---
name: codex
description: |
  OpenAI Codex CLI coding agent.
  Use when working with the codex candy.
---

# codex -- OpenAI Codex CLI

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
            - codex
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` — Required Node.js runtime parent dependency
- `/charly-coder:claude-code` — Sibling AI coding agent CLI bundled in same metalayers
- `/charly-coder:gemini` — Sibling Google Gemini CLI bundled alongside

## Related Commands
- `/charly-build:build` — Builds the candy (npm global install via package.json)
- `/charly-core:shell` — Interactive shell to invoke `codex` inside the container

## When to Use This Skill

Use when the user asks about:
- OpenAI Codex CLI in containers
- AI coding agent setup
- The `codex` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
