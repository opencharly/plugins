---
name: clawhub
description: |
  ClawHub CLI for searching and installing OpenClaw skills.
  Use when working with the clawhub candy.
---

# clawhub -- ClawHub skill registry CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `package.json` |
| Depends | `nodejs` |

## Usage

```yaml
# box charly.yml — composition is a child node, not a top-level list
my-box:
    candy:
        base: fedora
    my-box-candy:
        candy:
            - clawhub
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` — Required Node.js runtime parent dependency
- `/charly-openclaw:openclaw-full` — Metalayer bundling clawhub with codex/gemini/claude-code
- `/charly-openclaw:openclaw` — OpenClaw gateway service that consumes installed skills

## Related Commands
- `/charly-build:build` — Builds the candy (npm global install via package.json)
- `/charly-automation:openclaw-deploy` — OpenClaw gateway configuration where clawhub installs skills

## When to Use This Skill

Use when the user asks about:
- ClawHub skill registry
- Installing or searching OpenClaw skills
- The `clawhub` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
