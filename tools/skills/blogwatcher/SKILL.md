---
name: blogwatcher
description: |
  Blog/RSS feed monitor CLI.
  Use when working with the blogwatcher candy.
---

# blogwatcher -- Blog/RSS feed monitor

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
    candy: [blogwatcher]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` — Required Go runtime parent dependency
- `/charly-openclaw:openclaw-full` — Metalayer that bundles blogwatcher with other AI/agent CLIs

## Related Commands
- `/charly-build:build` — Builds the candy (Go install via a `run:` step)
- `/charly-core:shell` — Interactive shell to run blogwatcher inside the container

## When to Use This Skill

Use when the user asks about:
- Blog or RSS feed monitoring
- Go-based CLI tools for feed watching
- The `blogwatcher` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
