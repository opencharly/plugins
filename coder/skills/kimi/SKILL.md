---
name: kimi
description: |
  Moonshot Kimi Code CLI installed globally via npm from @moonshot-ai/kimi-code.
  Use when working with Kimi Code, AI coding assistants, or Moonshot tooling.
---

# kimi -- Moonshot Kimi Code CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs` |
| Install files | `charly.yml`, `package.json` |

## Usage

```yaml
# charly.yml
my-dev:
  candy:
    - kimi
```

## Used In Boxes

- No enabled boxes use this candy yet — composition into the AI-CLI metalayers
  (`hermes-full`, `openclaw-full`) and the coder boxes is the named
  `@github`-pin follow-up once the candy carries a published tag (see
  `/charly-build:reconcile`)

## Related Skills

- `/charly-coder:nodejs` -- required dependency (provides npm)
- `/charly-coder:claude-code`, `/charly-coder:codex`, `/charly-coder:gemini` — sibling AI CLIs (all share the npm-global install pattern)
- `/charly-image:layer` — candy authoring reference
- `/charly-check:check` — declarative testing framework (this candy's tests verify `${HOME}/.npm-global/bin/kimi`, the unpacked `@moonshot-ai/kimi-code` package, and `kimi --version`)

## When to Use This Skill

Use when the user asks about:

- Moonshot Kimi Code CLI in containers
- AI coding assistance tools
- The `kimi` candy
