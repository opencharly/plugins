---
name: songsee
description: |
  Audio spectrogram and visualization CLI.
  Use when working with the songsee candy.
---

# songsee -- Audio spectrogram CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (`run:` step) |
| Depends | `golang` |

## Environment

| Variable | Value |
|----------|-------|
| `GOPATH` | `~/go` |
| PATH append | `~/go/bin` |

## Usage

```yaml
# box charly.yml — compose the candy as an inline list in the box body
my-box:
  candy:
    base: fedora
    candy: [songsee]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` -- build/runtime dependency
- `/charly-openclaw:openclaw-full` -- parent metalayer that bundles songsee

## Related Commands
- `/charly-core:shell` -- run songsee CLI inside the container
- `/charly-automation:openclaw-deploy` -- audio skill registration in OpenClaw

## When to Use This Skill

Use when the user asks about:
- Audio spectrogram generation
- Audio visualization tools
- The `songsee` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
