---
name: sqlite
description: |
  SQLite database CLI.
  Use when working with the sqlite candy.
---

# sqlite -- SQLite database CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

RPM: `sqlite`

## Usage

```yaml
# box charly.yml — a box composes the candy through a <box>-candy child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - sqlite
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:dev-tools` -- common dev CLI bundle that pairs with sqlite
- `/charly-openclaw:openclaw-full` -- parent metalayer that bundles sqlite

## Related Commands
- `/charly-core:shell` -- run sqlite3 inside the container
- `/charly-core:cmd` -- one-shot sqlite query in a running service

## When to Use This Skill

Use when the user asks about:
- SQLite database in containers
- SQLite CLI tools
- The `sqlite` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
