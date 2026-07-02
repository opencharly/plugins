---
name: xurl
description: |
  X (Twitter) API CLI for posts, search, DMs, and media.
  Use when working with the xurl candy.
---

# xurl -- X/Twitter API CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `package.json` |
| Depends | `nodejs` |

## Usage

```yaml
# box charly.yml — name-first: compose the candy via a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - xurl
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` — runtime dependency
- `/charly-openclaw:openclaw-full` — metalayer that bundles xurl
- `/charly-hermes:hermes` — companion social/messaging agent

## Related Commands
- `/charly-core:shell` — run xurl inside the container
- `/charly-build:secrets` — store X/Twitter API credentials

## When to Use This Skill

Use when the user asks about:
- X/Twitter API access in containers
- Posting, searching, or managing Twitter/X content
- The `xurl` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
