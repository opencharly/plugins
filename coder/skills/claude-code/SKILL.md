---
name: claude-code
description: |
  Claude Code CLI installed globally via npm from @anthropic-ai/claude-code.
  Use when working with Claude Code, AI coding assistants, or Anthropic tooling.
---

# claude-code -- Claude Code CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs` |
| Install files | `charly.yml`, `task:` |

PATH additions: `~/.local/bin`

## Usage

```yaml
# charly.yml
my-dev:
  candy:
    - claude-code
```

## Used In Boxes

- No enabled boxes use this candy directly (standalone tool layer)

## Related Skills

- `/charly-coder:nodejs` -- required dependency (provides npm)
- `/charly-coder:codex`, `/charly-coder:gemini` — sibling AI CLIs (all three share the npm-global install pattern)
- `/charly-hermes:hermes-full-layer` — metalayer that bundles this with codex, gemini, dev-tools, devops-tools
- `/charly-hermes:hermes` — primary box that ships this CLI
- `/charly-image:layer` — candy authoring reference
- `/charly-check:check` — declarative testing framework (this candy's test verifies `${HOME}/.npm-global/bin/claude` + `claude --version`)

## When to Use This Skill

Use when the user asks about:

- Claude Code CLI in containers
- Anthropic AI coding tools
- The `claude-code` candy
