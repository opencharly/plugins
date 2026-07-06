---
name: playwright-layer
description: |
  Playwright browser automation (OpenClaw AI snapshots).
  Use when working with the playwright candy.
---

# playwright -- Browser automation

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `package.json` |
| Depends | `nodejs` |

## Usage

```yaml
# box or candy charly.yml — composition is an inline candy: list in the body
my-box:
  candy:
    base: fedora
    candy:
      - playwright
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` -- runtime dependency
- `/charly-openclaw:openclaw-full` -- parent metalayer that bundles playwright
- `/charly-selkies:chrome` -- browser commonly driven by playwright

## Related Commands
- `/charly-check:cdp` -- Chrome DevTools Protocol automation alternative
- `/charly-automation:openclaw-deploy` -- snapshot/skill configuration

## When to Use This Skill

Use when the user asks about:
- Playwright browser automation in containers
- OpenClaw AI snapshot support
- The `playwright` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
