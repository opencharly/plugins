---
name: forgecode
description: |
  Forge AI coding agent CLI (forgecode.dev) installed globally via npm from
  the `forgecode` package. Installs the `forge` binary.
  Use when working with Forge, forgecode.dev, or alternative AI coding agents.
---

# forgecode -- Forge AI Coding Agent CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs` |
| Install files | `charly.yml`, `package.json` |
| npm package | `forgecode` |
| Installed binary | `forge` (at `${HOME}/.npm-global/bin/forge`) |

## Usage

```yaml
# charly.yml
my-dev:
  candy:
    - forgecode
```

## Used In Boxes

- `hermes-full` (metalayer) -- bundles forgecode alongside claude-code / codex / gemini
- `hermes` box -- ships forgecode transitively via hermes-full

## Related Skills

- `/charly-coder:nodejs` -- required dependency (provides npm)
- `/charly-coder:claude-code`, `/charly-coder:codex`, `/charly-coder:gemini` -- sibling AI CLIs (codex and gemini share the same npm-global install pattern; claude-code uses the official native installer)
- `/charly-hermes:hermes-full-layer` -- metalayer that bundles this CLI
- `/charly-hermes:hermes` -- primary box that ships this CLI
- `/charly-image:layer` -- candy authoring reference
- `/charly-check:check` -- declarative testing framework (this candy verifies `${HOME}/.npm-global/bin/forge` + `forge --version`)

## When to Use This Skill

Use when the user asks about:

- Forge / forgecode / forgecode.dev in containers
- Alternative AI coding agents alongside Claude Code / Codex / Gemini
- The `forgecode` candy
