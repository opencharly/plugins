---
name: claude-code
description: |
  Claude Code CLI installed via the official native installer (https://claude.ai/install.sh),
  relocated to the system path /usr/local/bin/claude.
  Use when working with Claude Code, AI coding assistants, or Anthropic tooling.
---

# claude-code -- Claude Code CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | none (uses `curl` only; no nodejs) |
| Install files | `charly.yml` |

PATH additions: none needed — the binary is installed at the system path
`/usr/local/bin/claude`, which survives the deploy-time home-volume mount
(anything installed under `${HOME}` at build time is shadowed once a live pod
mounts its persistent home volume).

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

- `/charly-coder:codex`, `/charly-coder:gemini` — sibling AI CLIs (npm-global install pattern; claude-code moved off npm — the deprecated `@anthropic-ai/claude-code` package became a thin launcher that deferred its native-binary download to first runtime and failed in hermetic offline image builds)
- `/charly-hermes:hermes-full-layer` — metalayer that bundles this with codex, gemini, dev-tools, devops-tools
- `/charly-hermes:hermes` — primary box that ships this CLI
- `/charly-image:layer` — candy authoring reference
- `/charly-check:check` — declarative testing framework (this candy's test verifies `/usr/local/bin/claude` + `claude --version`)

## When to Use This Skill

Use when the user asks about:

- Claude Code CLI in containers
- Anthropic AI coding tools
- The `claude-code` candy
