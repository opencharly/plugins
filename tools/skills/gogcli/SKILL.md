---
name: gogcli
description: |
  Google Workspace CLI (Gmail, Calendar, Drive, Contacts, Sheets, Docs).
  Use when working with the gogcli candy.
---

# gogcli -- Google Workspace CLI

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
    candy: [gogcli]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` — required Go toolchain dependency
- `/charly-openclaw:openclaw-full` — metalayer that includes gogcli
- `/charly-tools:goplaces` — sibling Google API CLI in openclaw-full

## Related Commands
- `/charly-build:secrets` — provision Google OAuth credentials for gogcli
- `/charly-core:shell` — run gogcli interactively inside a container
- `/charly-build:build` — compiles gogcli via the Go builder during image build

## When to Use This Skill

Use when the user asks about:
- Google Workspace CLI access (Gmail, Calendar, Drive, Contacts, Sheets, Docs)
- Google API tools in containers
- The `gogcli` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
