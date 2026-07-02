---
name: hermes-layer
description: |
  Hermes self-improving AI agent by Nous Research with voice, messaging, and tool-calling.
  MUST be invoked before any work involving: the hermes candy, Hermes Agent configuration,
  hermes service setup, or hermes Python/npm dependencies.
---

# hermes -- Self-improving AI agent

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs`, `supervisord`, `ripgrep`, `ffmpeg`, `pipewire` |
| Volumes | `data` -> `/opt/data` |
| Aliases | `hermes` -> `hermes`, `hermes-agent` -> `hermes-agent` |
| Services | `hermes` (supervisord, autostart), `hermes-whatsapp` (supervisord, manual) |
| MCP accepts | `jupyter`, `chrome-devtools` |
| Install files | `pixi.toml`, `build.sh`, `task:` |
| RPM packages | `alsa-lib`, `portaudio` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `HERMES_HOME` | `/opt/data` |
| `TERMINAL_ENV` | `local` |

## Optional Environment Variables (env_accept)

These env vars are declared via `env_accept:` in `charly.yml` — hermes can use any LLM provider, so none are required:

| Variable | Description |
|----------|-------------|
| `OPENROUTER_API_KEY` | API key for OpenRouter LLM inference |
| `OLLAMA_API_KEY` | API key for Ollama Cloud inference (https://ollama.com) |
| `OLLAMA_HOST` | Local Ollama server URL (auto-injected by ollama candy `env_provide`) |
| `HERMES_MODEL` | Override default Hermes model (default depends on detected provider) |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token for messaging |
| `SLACK_BOT_TOKEN` | Slack bot token |
| `DISCORD_BOT_TOKEN` | Discord bot token |
| `CHARLY_MCP_SERVERS` | JSON array of MCP servers (auto-injected by mcp_provide candies) |

Provide via `charly config hermes -e OLLAMA_API_KEY=...` or workspace `.secrets` / `.env` file.

## Automatic LLM Provider Configuration

The `hermes-entrypoint` performs a **single-phase, first-start-only** configuration that registers ALL available LLM providers AND MCP servers in one pass. Guarded by a `# charly:auto-configured` sentinel in `config.yaml`. To reconfigure: delete `config.yaml` and restart. API keys are synced to `.env` on every start to handle rotation.

| Priority | Env var | Provider | Default model |
|----------|---------|----------|---------------|
| 1 | `OLLAMA_HOST` | Local Ollama (`custom`) | `qwen2.5-coder:32b` |
| 2 | `OLLAMA_API_KEY` | Ollama Cloud (`custom`) | `kimi-k2.5:cloud` |
| 3 | `OPENROUTER_API_KEY` | OpenRouter (built-in) | `qwen/qwen3.6-plus:free` |

**How it works:**
- **First start:** Registers ALL providers whose env vars are set into `config.yaml` as `custom_providers` entries, and configures any discovered MCP servers from `CHARLY_MCP_SERVERS` (e.g., `jupyter` at `:8888/mcp`, `chrome-devtools` at `:9224/mcp`). Priority determines only the default model and auxiliary task routing. Writes a `# charly:auto-configured` sentinel to prevent re-patching after user customization
- **Key insight:** When new MCP servers are added to `CHARLY_MCP_SERVERS` after initial configuration, hermes will NOT pick them up automatically. Delete `config.yaml` and restart: `charly shell <image> -c "rm /opt/data/config.yaml" && charly service restart <image> hermes`
- **Every start:** Syncs API keys to `.env` to handle key rotation
- Override the default model with `HERMES_MODEL` env var
- Switch between registered providers mid-session: `/model custom:ollama-cloud:kimi-k2.5:cloud` or `hermes chat --provider openrouter`
- To force full reconfigure: delete `/opt/data/config.yaml`, update env vars, restart

## MCP Server Discovery

The hermes entrypoint auto-discovers MCP servers from the `CHARLY_MCP_SERVERS` environment variable at first start. Servers are configured in `config.yaml` under the `mcp_servers:` key (hermes native YAML map format).

**Diagnostics:**
- `hermes mcp list` -- shows registered MCP servers
- `hermes mcp test <name>` -- tests connection to a specific server

**Runtime:**
- Tools are registered as `mcp_<server_name>_<tool_name>`
- Reload MCP servers at runtime: `/reload-mcp` in interactive chat

**Example:** The `jupyter` candy provides 11 tools (notebook_list, cell_execute, cell_update, etc.) via its MCP server at `http://<container>:8888/mcp`. Noun-shaped surface (notebook_*/cell_* + notebook_list_users + room_list); clients do not manage CRDT rooms.

## Architecture

This is a **Tier 2 environment-owner candy** with `pixi.toml` defining the Python 3.13 environment. Follows the **selkies build.sh pattern**: the `build.sh` script runs in the pixi builder stage (which has gcc, nodejs, npm) to clone the hermes-agent repo, pip install it, and set up the WhatsApp bridge.

### Build Pipeline

1. **pixi.toml** -- Python 3.13 + all hermes-agent `[all]` PyPI dependencies (openai, anthropic, httpx, rich, pydantic, telegram, discord, slack, faster-whisper, sounddevice, elevenlabs, mcp, and more)
2. **build.sh** -- Runs in builder stage:
   - `git clone --depth 1` hermes-agent from GitHub
   - `pip install --no-deps .` into pixi env (non-editable)
   - `npm install` in project root (agent-browser, camoufox-browser)
   - `npm install` in `scripts/whatsapp-bridge/`
   - Copies full source tree to `$HOME/hermes-agent` for runtime files
3. A `copy:` task delivers `hermes-entrypoint` wrapper to `~/.local/bin/`

### Runtime Entrypoint

The `hermes-entrypoint` script (run by supervisord) initializes the data volume on first start:
- Creates `$HERMES_HOME/{cron,sessions,logs,hooks,memories,skills}`
- Copies `.env.example`, `config.yaml`, `SOUL.md` defaults if not present
- Auto-configures LLM provider from environment (see Automatic LLM Provider Configuration above)
- Syncs bundled skills via `skills_sync.py`
- Execs `hermes`

### npm Dependencies

Agent-browser and camoufox-browser are installed in the **project-level** `node_modules/` (via `build.sh`), not globally. Hermes expects these as local imports from its source tree at `~/hermes-agent/`.

### Browser Integration

Hermes has browser tools (`browser_navigate`, `browser_click`, `browser_snapshot`, etc.) enabled by default. The browser backend depends on configuration:

| Priority | Env var | Backend | Description |
|----------|---------|---------|-------------|
| 1 | `CAMOFOX_URL` | Camoufox REST API | Anti-detection Firefox (explicit opt-in) |
| 2 | `BROWSER_CDP_URL` | CDP override (`agent-browser --cdp`) | Connect to existing Chrome |
| 3 | Browserbase configured | Cloud session | Remote cloud browser |
| 4 | *(default)* | Local headless (`agent-browser --session`) | Requires Playwright Chromium |

**Cross-container with selkies-desktop:** Deploy `hermes` alongside `selkies-desktop` as separate pods. The chrome candy's `env_provide: BROWSER_CDP_URL` injects `http://charly-selkies-desktop:9222` into the hermes quadlet via `charly config --update-all`. Hermes uses the desktop Chrome — the user sees hermes browsing in real-time at `:3000`. The `cdp-proxy` in the chrome candy rewrites Host headers for Chrome 146+ compatibility.

**In standalone boxs** (`hermes-playwright`): The `hermes-playwright` candy provides Playwright Chromium for local headless mode (backend #4).

**In headless boxes** (`hermes`): No browser binary installed. Browser tools fail unless `BROWSER_CDP_URL` points to an external Chrome (cross-container via `env_provide`).

**Cross-container:** Deploy Chrome/Selkies in one container and hermes in another. `charly config` injects `BROWSER_CDP_URL=http://charly-<chrome-image>:9222` into hermes's quadlet via `env_provide`. Port 9222 is reachable via the chrome candy's `port_relay`.

Runtime commands: `/browser connect [url]`, `/browser disconnect`, `/browser status`.

### WhatsApp Bridge

The WhatsApp bridge is a separate Node.js service with `autostart=false` in supervisord. Enable via:
```bash
charly service start hermes hermes-whatsapp
```

## Excluded Dependencies

- `matrix` extra -- upstream-broken libolm (archived, C++ errors with Clang 21+)
- `rl` extra -- requires git dependencies (atropos, tinker)
- `yc-bench` extra -- requires git dependency

## Usage

```yaml
# charly.yml
hermes:
  base: fedora
  candy:
    - agent-forwarding
    - hermes-full
    - dbus
```

## Related Candies

- `/charly-coder:nodejs` -- Node.js runtime dependency
- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-tools:ripgrep` -- fast search dependency
- `/charly-selkies:ffmpeg` -- audio/video processing (negativo17 nonfree codecs)
- `/charly-selkies:pipewire` -- audio support for voice features
- `/charly-hermes:hermes-playwright` -- optional Playwright Chromium browser (standalone headless mode)
- `/charly-selkies:chrome` -- provides `BROWSER_CDP_URL` via `env_provide` for shared browser in desktop boxes
- `/charly-jupyter:jupyter` -- MCP server provider (`mcp_provide: jupyter`)
- `/charly-selkies:chrome-devtools-mcp` -- Chrome DevTools MCP server (`mcp_provide: chrome-devtools`, 29 tools)

## Related Commands

- `/charly-check:cdp` — CDP automation; hermes uses the same Chrome endpoint via `BROWSER_CDP_URL`
- `/charly-core:charly-config` — Injects `BROWSER_CDP_URL` and `CHARLY_MCP_SERVERS` via pod-aware `env_provide`/`mcp_provide`
- `/charly-build:charly-mcp-cmd` — verify that the MCP servers hermes discovers (`jupyter`, `chrome-devtools`) are alive and exposing expected tools before hermes tries to call them: `charly check live jupyter --filter mcp`, `charly check live <image> --filter mcp`. Useful when hermes reports tool-call failures and you need to isolate whether the server or the agent is at fault.

## Related Boxes

- `/charly-hermes:hermes` -- full-featured standalone (claude-code + codex + gemini + dev-tools + devops-tools + charly)
- `/charly-hermes:hermes-playwright` -- agent with Playwright Chromium (standalone headless)
- `/charly-openwebui:openwebui` -- alternative web UI frontend with similar MCP/LLM auto-config pattern
- `/charly-selkies:selkies-labwc` -- deploy alongside for shared Chrome browser (cross-container CDP)
- `/charly-jupyter:jupyter` -- deploy alongside for MCP notebook access (cross-container MCP)

## When to Use This Skill

**MUST be invoked** when the task involves the hermes candy, Hermes Agent setup, hermes service configuration, hermes Python dependencies, or the hermes entrypoint. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
