---
name: gifgrep
description: |
  GIF search and download CLI.
  Use when working with the gifgrep candy.
---

# gifgrep -- GIF search and download

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
    candy: [gifgrep]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` — required Go toolchain dependency
- `/charly-openclaw:openclaw-full` — metalayer that includes gifgrep
- `/charly-tools:goplaces` — sibling Go-based CLI in openclaw-full

## Related Commands
- `/charly-build:build` — compiles gifgrep via the Go builder during image build
- `/charly-core:shell` — run gifgrep interactively inside a container

## When to Use This Skill

Use when the user asks about:
- GIF search and download tools
- Go-based GIF CLI
- The `gifgrep` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
