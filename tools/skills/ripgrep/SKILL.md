---
name: ripgrep
description: |
  Fast recursive text search (rg).
  Use when working with the ripgrep candy.
---

# ripgrep -- Fast text search

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

RPM: `ripgrep`

## Usage

```yaml
# box charly.yml — name-first: compose the candy via a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - ripgrep
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:dev-tools` -- bundles ripgrep alongside other CLI utilities
- `/charly-openclaw:openclaw-full` -- parent metalayer that bundles ripgrep

## Related Commands
- `/charly-core:shell` -- run rg interactively inside the container
- `/charly-core:cmd` -- one-shot rg invocation in a running service

## When to Use This Skill

Use when the user asks about:
- ripgrep (rg) in containers
- Fast text search tools
- The `ripgrep` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
