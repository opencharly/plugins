---
name: openclaw-full
description: |
  Headless OpenClaw with all tool candies. No desktop environment.
  MUST be invoked before building, deploying, or troubleshooting the openclaw-full box.
---

# openclaw-full

Headless OpenClaw box with maximal tool/skill coverage. No desktop, no VNC.

## Box Properties

| Property | Value |
|----------|-------|
| Base | cachyos |
| Candies | agent-forwarding, openclaw-full |
| Platforms | linux/amd64 |
| Ports | 18789 (gateway) |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `cachyos` (external base, Arch-derived — pacman/AUR)
2. `openclaw-full` metalayer (27 layers, no system browser):
   - `openclaw` — AI gateway
   - `claude-code` — Claude Code CLI
   - 25 tool candies (codex, gemini, clawhub, mcporter, oracle, xurl, summarize, playwright, blogwatcher, gifgrep, wacli, goplaces, songsee, sag, camsnap, gogcli, ordercli, himalaya, uv, nano-pdf, gh, tmux, ffmpeg, ripgrep, sqlite)

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 18789 | OpenClaw gateway | HTTP |

## Quick Start

```bash
charly box build openclaw-full
charly config openclaw-full
charly start openclaw-full
```

## Key Candies

- `/charly-openclaw:openclaw-full` — Metalayer composition (all tools)
- `/charly-openclaw:openclaw` — AI gateway service

## Related Boxes

- `/charly-openclaw:openclaw` — minimal (gateway only)

## When to Use This Skill

**MUST be invoked** when the task involves the openclaw-full box or the headless maximal OpenClaw deployment.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
