---
name: camsnap
description: |
  RTSP/ONVIF camera snapshot and clip CLI.
  Use when working with the camsnap candy.
---

# camsnap -- Camera snapshot CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (a `run:` install step) |
| Depends | `golang` |

## Environment

| Variable | Value |
|----------|-------|
| `GOPATH` | `~/go` |
| PATH append | `~/go/bin` |

## Usage

```yaml
# a box composing this candy — the candy list is a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - camsnap
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` — Required Go runtime parent dependency
- `/charly-openclaw:openclaw-full` — Metalayer that bundles camsnap with other agent CLIs

## Related Commands
- `/charly-build:build` — Builds the candy (Go install via a `command:` run step)
- `/charly-core:shell` — Interactive shell to run camsnap inside the container

## When to Use This Skill

Use when the user asks about:
- RTSP or ONVIF camera snapshots
- Camera snapshot/clip tools
- The `camsnap` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, `run:`/`check:` step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
