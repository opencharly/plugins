---
name: hermes-full-layer
description: |
  Hermes agent with AI CLIs (Claude Code, Codex, Gemini), developer tools, DevOps tools, and charly.
  Use when working with the hermes-full metalayer or full-featured standalone hermes deployments.
---

# Candy: hermes-full

Metalayer composing Hermes AI agent with a complete tool suite for standalone deployment. No browser included — use with `selkies-desktop` via cross-container `env_provide: BROWSER_CDP_URL` for shared browser automation.

## Composition

```yaml
# the hermes-full metalayer is a candy entity; composition is an inline candy: list in the body
hermes-full:
  candy:
    version: 2026.156.1921   # mandatory CalVer
    candy:                   # the candies it pulls in
      - hermes          # AI agent with browser tools, MCP, LLM auto-config
      - claude-code     # Anthropic Claude Code CLI
      - codex           # OpenAI Codex CLI
      - gemini          # Google Gemini CLI
      - dev-tools       # bat, ripgrep, neovim, gh, direnv, fd-find, htop, etc.
      - devops-tools    # AWS CLI, Scaleway, kubectx, OpenTofu, wrangler, jq, rsync
      - charly              # OpenCharly CLI for in-container management
      - tmux            # Terminal multiplexer for persistent sessions
```

## Browser Integration

The hermes candy declares `env_accept: BROWSER_CDP_URL`. When deployed alongside a `selkies-desktop` container, the chrome candy's `env_provide` injects `BROWSER_CDP_URL=http://charly-selkies-desktop:9222` into the hermes quadlet via `charly config --update-all`. Hermes browser tools (`browser_navigate`, `browser_click`, `browser_snapshot`) then control the desktop Chrome across the container network.

Without a browser provider, hermes browser tools fall back to local headless mode (requires `hermes-playwright` candy) or are unavailable.

## Usage

```yaml
# charly.yml
hermes:
  candy:
    base: fedora
    candy:
      - agent-forwarding
      - hermes-full
      - dbus
```

## Related Candies

- `/charly-hermes:hermes` — Core Hermes agent (LLM providers, MCP, browser dispatch)
- `/charly-coder:claude-code` — Anthropic Claude Code CLI
- `/charly-coder:codex` — OpenAI Codex CLI
- `/charly-coder:gemini` — Google Gemini CLI
- `/charly-coder:dev-tools` — Developer CLI utilities
- `/charly-coder:devops-tools` — Cloud and infrastructure tools
- `/charly-tools:charly` — OpenCharly CLI binary
- `/charly-infrastructure:tmux-layer` — Terminal multiplexer for persistent sessions (`charly tmux` commands)
- `/charly-selkies:chrome` — Provides `BROWSER_CDP_URL` (cross-container, from selkies-desktop)
- `/charly-selkies:chrome-devtools-mcp` — Chrome DevTools MCP server (auto-discovered via `mcp_provide`, 29 tools)
- `/charly-jupyter:jupyter-mcp` — JupyterLab CRDT MCP server (auto-discovered via `mcp_provide`, 11 tools: notebook_*/cell_* + notebook_list_users + room_list; auto-attach single-room invariant)
- `/charly-build:charly-mcp-cmd` — the declarative `mcp:` check verb (run via `charly check live <image> --filter mcp`), served out-of-process by candy/plugin-mcp, to verify either of the above is alive and exposing the expected tool catalog before hermes tries to invoke them

## Related Boxes

- `/charly-hermes:hermes` — Standalone full-featured hermes box
- `/charly-hermes:hermes-playwright` — Hermes with local Playwright Chromium

## When to Use This Skill

Use when working with the `hermes-full` metalayer, full-featured standalone hermes deployments, or the composition of hermes with AI CLIs and developer tools.

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
