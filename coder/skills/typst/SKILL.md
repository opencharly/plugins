---
name: typst
description: |
  Typst document processor binary for typesetting and document generation.
  Use when working with Typst, document compilation, or typesetting tools.
---

# typst -- document processor

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `task:` |

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - typst
```

## Used In Boxes

- (none currently enabled)

## Related Candies
- `/charly-tools:vscode` — editor sibling

## Related Commands
- `/charly-core:shell` — run typst inside the container
- `/charly-build:build` — rebuild after candy changes

## When to Use This Skill

Use when the user asks about:

- Typst document processor installation
- Document typesetting or compilation
- The typst binary in containers

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
