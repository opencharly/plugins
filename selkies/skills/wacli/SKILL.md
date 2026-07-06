---
name: wacli
description: |
  WhatsApp CLI for message sending and history sync.
  Use when working with the wacli candy.
---

# wacli -- WhatsApp CLI

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
# a box composing this candy — the candy list is inline
my-box:
  candy:
    base: fedora
    candy: [wacli]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` — Go toolchain dependency
- `/charly-openclaw:openclaw-full` — metalayer that bundles wacli
- `/charly-hermes:hermes` — companion messaging stack with WhatsApp bridge

## Related Commands
- `/charly-core:shell` — run wacli inside the container
- `/charly-build:secrets` — store WhatsApp session credentials

## When to Use This Skill

Use when the user asks about:
- WhatsApp messaging from containers
- WhatsApp history sync
- The `wacli` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, `run:`/`check:` step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
