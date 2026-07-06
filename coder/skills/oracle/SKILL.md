---
name: oracle
description: |
  Oracle CLI for prompt bundling and multi-engine AI queries.
  Use when working with the oracle candy.
---

# oracle -- Prompt bundling CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `package.json` |
| Depends | `nodejs` |

## Usage

```yaml
# box charly.yml — compose the candy as an inline list in the box body
my-box:
    candy:
        base: fedora
        candy: [oracle]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` -- runtime dependency
- `/charly-openclaw:openclaw-full` -- parent metalayer that bundles oracle

## Related Commands
- `/charly-automation:openclaw-deploy` -- gateway/skill configuration
- `/charly-core:shell` -- run oracle CLI inside the container

## When to Use This Skill

Use when the user asks about:
- Prompt bundling for AI queries
- Multi-engine AI query tools
- The `oracle` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
