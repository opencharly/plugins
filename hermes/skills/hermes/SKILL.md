---
name: hermes
description: |
  Full-featured standalone Hermes AI agent with AI CLIs, dev tools, DevOps tools, and charly.
  MUST be invoked before building, deploying, configuring, or troubleshooting the hermes box.
---

# Box: hermes

Full-featured standalone Hermes AI agent. No browser or desktop — designed for cross-container deployment alongside `selkies-desktop` (shared Chrome via `BROWSER_CDP_URL`) and `jupyter` (MCP notebooks via `CHARLY_MCP_SERVERS`).

## Definition

```yaml
hermes:
  base: fedora
  candy:
    - agent-forwarding
    - hermes-full      # hermes + claude-code + codex + gemini + dev-tools + devops-tools + charly + tmux
    - dbus
```

## Candy Stack

| Candy | Purpose |
|-------|---------|
| `agent-forwarding` | SSH + GPG agent forwarding into container |
| `hermes` | AI agent with LLM auto-config, MCP, browser tools |
| `claude-code` | Anthropic Claude Code CLI |
| `codex` | OpenAI Codex CLI |
| `gemini` | Google Gemini CLI |
| `dev-tools` | bat, ripgrep, neovim, gh, direnv, fd-find, htop, podman-compose, etc. |
| `devops-tools` | AWS CLI, Scaleway, kubectx/kubens, OpenTofu, wrangler, bind-utils, jq, rsync |
| `charly` | OpenCharly CLI for in-container management |
| `tmux` | Terminal multiplexer for persistent sessions |
| `dbus` | D-Bus session bus |

## Quick Start

```bash
charly box build hermes
charly config hermes -e OLLAMA_API_KEY=your-key   # or OPENROUTER_API_KEY
charly start hermes
charly shell hermes -c "hermes chat"
```

## Configuration

The hermes entrypoint performs a **single-phase, first-start-only** auto-configuration of LLM providers and MCP servers. Guarded by `# charly:auto-configured` sentinel in `config.yaml`. To reconfigure: delete `/opt/data/config.yaml` and restart. API keys are synced to `.env` on every start (handles rotation).

LLM provider based on which env var is set:

| Priority | Env var | Provider | Default model |
|----------|---------|----------|---------------|
| 1 | `OLLAMA_HOST` | Local Ollama | `qwen2.5-coder:32b` |
| 2 | `OLLAMA_API_KEY` | Ollama Cloud | `kimi-k2.5:cloud` |
| 3 | `OPENROUTER_API_KEY` | OpenRouter | `qwen/qwen3.6-plus:free` |

Override the default model with `HERMES_MODEL` env var. Additional `env_accept`:

| Variable | Description |
|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Telegram bot token for messaging |
| `SLACK_BOT_TOKEN` | Slack bot token |
| `DISCORD_BOT_TOKEN` | Discord bot token |

```bash
# Ollama Cloud
charly config hermes -e OLLAMA_API_KEY=your-key

# OpenRouter with custom model
charly config hermes -e OPENROUTER_API_KEY=sk-or-xxx -e HERMES_MODEL=google/gemini-2.5-flash

# Local Ollama (OLLAMA_HOST auto-injected by charly config ollama --update-all)
charly config hermes

# Or via .env file in the data volume
charly shell hermes -c "vi /opt/data/.env"
```

The data volume (`/opt/data`) persists: sessions, skills, memories, logs, config, and `.env`.

## Cross-Container Service Discovery

Deploy alongside provider containers for full functionality:

```bash
# 1. Deploy selkies-desktop (provides BROWSER_CDP_URL)
charly config selkies-desktop
charly start selkies-desktop

# 2. Deploy jupyter (provides jupyter MCP server)
charly config jupyter --update-all
charly start jupyter

# 3. Deploy hermes (consumes both)
charly config hermes -e OLLAMA_API_KEY=... --update-all
charly start hermes
```

Hermes receives:
- `BROWSER_CDP_URL=http://charly-selkies-desktop:9222` — controls desktop Chrome
- `CHARLY_MCP_SERVERS=[{"name":"jupyter","url":"http://charly-jupyter:8888/mcp"},{"name":"chrome-devtools","url":"http://charly-selkies-desktop:9224/mcp"}]` — notebook manipulation + browser DevTools MCP

## MCP Server Discovery

When co-deployed with services that declare `mcp_provide` (e.g., jupyter), hermes auto-discovers and connects to their MCP servers at first start. The `CHARLY_MCP_SERVERS` JSON env var is injected by `charly config` and the entrypoint writes the servers into `config.yaml` under `mcp_servers:`.

```bash
# Verify MCP connection
charly shell hermes -c "hermes mcp list"                    # Shows registered servers
charly shell hermes -c "hermes mcp test jupyter"      # Tests connection (expects 11 tools)
```

## Key Candies

- `/charly-hermes:hermes-full-layer` — Metalayer composition details
- `/charly-hermes:hermes` — Core agent (env_accept, browser dispatch, LLM config)
- `/charly-selkies:chrome` — Provides `BROWSER_CDP_URL` (from selkies-desktop)
- `/charly-selkies:chrome-devtools-mcp` — Chrome DevTools MCP server on port 9224 (from selkies-desktop)

## Related Boxes

- `/charly-hermes:hermes-playwright` — Hermes with local Playwright Chromium
- `/charly-selkies:selkies-labwc` — Desktop with Chrome (cross-container browser provider)
- `/charly-jupyter:jupyter` — JupyterLab with MCP (cross-container MCP provider)

## Verification

```bash
charly status hermes
charly service status hermes                    # hermes: RUNNING
charly shell hermes -c "hermes --version"
charly shell hermes -c "claude --version"
charly shell hermes -c "codex --version"
charly shell hermes -c "gemini --version"
charly shell hermes -c "charly version"
charly shell hermes -c "echo BROWSER_CDP_URL=\$BROWSER_CDP_URL"
charly shell hermes -c "echo CHARLY_MCP_SERVERS=\$CHARLY_MCP_SERVERS"
charly shell hermes -c "hermes mcp list"              # Should show chrome-devtools, jupyter
```

## Test Coverage

Latest `charly check live hermes` run: **50 passed, 0 failed, 0 skipped**.
Covers all 4 AI CLIs — `claude` at `/usr/local/bin/claude` (native
installer), `codex` / `gemini` at `${HOME}/.npm-global/bin/`
+ pixi's `hermes` at `${HOME}/.pixi/envs/default/bin/hermes`, plus
dev-tools (rg, bat, gh, fastfetch, nvim, htop) and devops-tools (aws,
scw, kubectx, kubens, tofu, jq). Deploy-scope: pipewire + hermes
services up, `/opt/data` volume mounted. Uses `supervisorctl pid` for
liveness (hermes-whatsapp is autostart=false — see `/charly-check:check` Gotcha #4).

## Related Skills

- `/charly-hermes:hermes-full-layer`, `/charly-hermes:hermes`, `/charly-coder:claude-code`,
  `/charly-coder:codex`, `/charly-coder:gemini`, `/charly-coder:dev-tools`,
  `/charly-coder:devops-tools`
- `/charly-check:check` — declarative testing framework + supervisord gotchas
- `/charly-core:charly-config` — `CHARLY_MCP_SERVERS` auto-discovery + secret provisioning
- `/charly-build:charly-mcp-cmd` — verify each MCP server in `CHARLY_MCP_SERVERS` is actually alive before debugging hermes tool-call failures; `charly check live <provider-image> --filter mcp` shows exactly what hermes will see
- `/charly-selkies:selkies-labwc` — companion for shared browser (CDP)
- `/charly-jupyter:jupyter` — MCP notebook tools auto-discovered

## When to Use This Skill

**MUST be invoked** before building, deploying, configuring, or troubleshooting the hermes box.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
