---
name: openclaw-full-layer
description: |
  Maximal OpenClaw deployment (gateway + browser + all feasible tools/skills).
  Use when working with the openclaw-full candy.
---

# openclaw-full -- Maximal OpenClaw deployment

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (metalayer, layers only) |
| Depends | none (composes other candies) |

## Composed Candies

This metalayer includes the following 25 candies:

- `openclaw` -- AI gateway
- `chrome` -- Google Chrome browser
- `claude-code` -- Claude Code CLI
- `codex` -- OpenAI Codex CLI
- `gemini` -- Google Gemini CLI
- `clawhub` -- ClawHub skill registry CLI
- `mcporter` -- MCP server CLI
- `oracle` -- Prompt bundling CLI
- `xurl` -- X/Twitter API CLI
- `summarize` -- URL/transcript extractor
- `playwright` -- Browser automation
- `blogwatcher` -- Blog/RSS feed monitor
- `gifgrep` -- GIF search and download
- `wacli` -- WhatsApp CLI
- `goplaces` -- Google Places API CLI
- `songsee` -- Audio spectrogram
- `sag` -- ElevenLabs TTS CLI
- `camsnap` -- Camera snapshot CLI
- `gogcli` -- Google Workspace CLI
- `ordercli` -- Food delivery order CLI
- `himalaya` -- Email CLI
- `uv` -- Python package manager
- `nano-pdf` -- PDF editing CLI
- `gh` -- GitHub CLI
- `tmux` -- Terminal multiplexer
- `ffmpeg` -- FFmpeg multimedia
- `ripgrep` -- Fast text search
- `sqlite` -- SQLite database CLI

## Usage

```yaml
# box charly.yml — composition is an inline candy: list in the body
openclaw-full-box:
    candy:
        base: fedora
        candy:
            - openclaw-full
```

## Used In Boxes

- `openclaw-full`

## Related Candies
- `/charly-openclaw:openclaw` — base gateway layer included in this metalayer
- `/charly-selkies:sway-desktop-vnc` — desktop candy paired in sway-browser boxes

## Related Commands
- `/charly-automation:openclaw-deploy` — gateway configuration, model auth, and channel setup
- `/charly-build:build` — builds the metalayer composition into a box
- `/charly-core:charly-config` — sets up secrets and quadlets for openclaw-full boxes

## When to Use This Skill

Use when the user asks about:
- Full OpenClaw deployment with all tools
- The `openclaw-full` metalayer composition
- Which tools are included in the maximal OpenClaw box
- The `openclaw-full` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
