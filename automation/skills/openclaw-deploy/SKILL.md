---
name: openclaw-deploy
description: |
  Topic skill (no dedicated `charly openclaw` command — the surface is candy composition + box deployment). MUST be invoked before any work involving: OpenClaw gateway configuration, model auth, browser integration, channel setup, or any box composing `openclaw-*` candies (`openclaw`, `openclaw-full`, or a custom box composing `openclaw`/`openclaw-full` + `sway-desktop`).
---

# OpenClaw - AI Gateway Configuration

## Overview

OpenClaw is an AI gateway that connects LLM agents to messaging channels (WhatsApp, Telegram, Discord, Slack, Signal, iMessage, IRC, Teams) and exposes them via a WebSocket API, CLI, and web Control UI. It runs as a Node.js process with an embedded agent runtime, model failover, browser automation, and multi-agent routing.

In OpenCharly, OpenClaw runs as a supervisord service inside containers. The `openclaw` candy provides the npm package; compose it with the `sway-desktop` metalayer (full Sway desktop + Chrome browser + VNC) for browser-based workflows like OAuth and web automation. For a desktop+browser box, compose your own from the candies (shown below); for non-browser channels use the headless `openclaw` / `openclaw-full` boxes.

The gateway listens on port 18789 (WebSocket + HTTP). All CLI commands (`openclaw *`) connect to the gateway WebSocket. The Control UI is served at the gateway root URL. Config is stored in `~/.openclaw/openclaw.json` (JSON5 format).

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Gateway health | `openclaw health` | Check gateway connectivity |
| Gateway status | `openclaw status --all` | Full status with channels |
| Model status | `openclaw models status` | Show model, auth, and usage |
| Browser status | `openclaw browser status` | Show browser connection state |
| Browser tabs | `openclaw browser tabs` | List open Chrome tabs |
| Open URL | `openclaw browser open <url>` | Open URL in Chrome |
| Page snapshot | `openclaw browser snapshot` | Accessible page structure (AI refs) |
| Screenshot | `openclaw browser screenshot` | Capture PNG to media dir |
| Config get/set | `openclaw config get/set <key> <val>` | Read/write config values |
| Doctor | `openclaw doctor --fix` | Health checks + auto-fixes |
| Security audit | `openclaw security audit` | Check security posture |
| Channel login | `openclaw channels login --channel <ch>` | Connect a messaging channel |
| Agent message | `openclaw agent --agent main --message "..."` | Send test prompt |
| Setup wizard | `openclaw configure` | Interactive config wizard |
| Logs | `openclaw logs --follow` | Tail gateway logs |

For container lifecycle, use `charly` commands -- see `/charly-core:service`.

## OpenCharly Integration

### Candy

The `openclaw` candy (`candy/openclaw/`) depends on `nodejs` and `supervisord`. It installs the `openclaw` npm package globally, exposes port 18789, declares a `data` volume at `~/.openclaw`, and runs as a supervisord service:

```
[program:openclaw]
command=%(ENV_HOME)s/.npm-global/bin/openclaw gateway --port 18789
```

The gateway binds to loopback only (no `--bind lan`). External access is handled by port_relay (socat), which forwards from the container interface to loopback. This avoids CORS origin checks entirely — the gateway only ever sees loopback connections.

### Box

Compose your own desktop+browser box — e.g. an `openclaw-desktop` entry in `charly.yml` combining `openclaw-full` + `sway-desktop` on a Fedora base:

```yaml
openclaw-desktop:
  candy:
    base: fedora
    candy:
      - agent-forwarding
      - openclaw-full
      - sway-desktop
      - dbus
      - charly
```

A box declares no ports of its own — the composed candies publish them (openclaw
18789, wayvnc 5900, chrome 9222/9224) and `charly config -p` remaps them at deploy
time. The resulting box exposes:

| Port | Service | Protocol |
|------|---------|----------|
| 18789 | Gateway WebSocket + Control UI | HTTP |
| 5900 | VNC (wayvnc) | TCP |
| 9222 | Chrome DevTools | HTTP |

Tunnel config exposes all ports via Tailscale (`ports: all`). Platform: linux/amd64 only.

### Host Alias

```bash
charly alias add openclaw openclaw-desktop
# Now: openclaw --help  (runs inside the container)
```

### Lifecycle

```bash
charly box build openclaw-desktop         # Build image
charly config openclaw-desktop        # Generate quadlet, daemon-reload
charly start openclaw-desktop         # Start via systemd
charly stop openclaw-desktop          # Stop
charly status openclaw-desktop        # Check systemd status
charly logs openclaw-desktop -f       # Follow container logs
```

## Gateway Configuration

### Required Settings for Container Use

The gateway binds to loopback only (no `--bind lan`). Only one config value is required before the gateway will start:

```bash
openclaw config set gateway.mode local
```

Without `gateway.mode=local`, the gateway refuses to start.

`dangerouslyAllowHostHeaderOriginFallback` is **NOT needed** because port_relay (socat) handles external access — the gateway only sees loopback connections, so no CORS origin checks are triggered.

For Chrome integration, also set:

```bash
openclaw config set browser.cdpUrl "http://127.0.0.1:9222"
```

After setting these, restart the gateway:

```bash
supervisorctl restart openclaw
```

### Auth Modes

| Mode | Description |
|------|-------------|
| `none` | No auth (loopback only) |
| `token` | Bearer token in WebSocket handshake |
| `password` | Password auth |
| `trusted-proxy` | Proxy handles auth (e.g., Tailscale identity headers) |

### Bind Modes

| Mode | Description |
|------|-------------|
| `loopback` | 127.0.0.1 only (default) |
| `lan` | All interfaces (0.0.0.0) -- requires auth |
| `tailnet` | Tailscale interface only |

### Health Checks

```bash
openclaw health --json                 # Gateway health
openclaw doctor --fix                  # Diagnose and fix issues
openclaw status --all --deep           # Full status with channels
# HTTP endpoints on gateway port:
# GET /healthz  -- liveness
# GET /readyz   -- readiness
```

## Model Configuration

### Primary Model + Fallbacks

```json5
// In ~/.openclaw/openclaw.json
agents: {
  defaults: {
    model: {
      primary: "openai-codex/gpt-5.4",
      fallbacks: ["anthropic/claude-sonnet-4-5"]
    }
  }
}
```

### OAuth Auth (OpenAI Codex)

**Critical:** The `openclaw models auth login` TUI requires a real terminal to complete the post-callback token exchange. Do not pipe or redirect it. Use the typed persistent terminal provider (see `/charly-automation:tmux`):

```bash
RUN=0198f140-6b7a-7b90-8a10-aabbccddee01
TARGET='{"deployment":"openclaw"}'
PROFILE='{"name":"openclaw-oauth","entrypoint":["openclaw","models","auth","login","--provider","openai-codex","--set-default"],"cols":120,"rows":40,"persistence":"required","transcript":"both"}'

# Start with a real PTY, then read normalized screen/evidence without redirecting the TUI.
charly agent terminal launch "$PROFILE" --target "$TARGET" --run-id "$RUN"
charly agent terminal snapshot "$PROFILE" --target "$TARGET" --run-id "$RUN"
charly agent terminal transcript "$RUN"

# 3. Drive the browser via cdp:/vnc: plan steps (the cdp: verb is served
#    out-of-process by candy/plugin-cdp): cdp: open the OAuth URL, then locate
#    "Continue with Google" and "Continue" (consent) with cdp: coords on
#    'button._buttonStyleFix_wvuha_65' / 'button._primary_3rdp0_107' and deliver
#    each click via the vnc: verb (chrome:// + anti-automation pages need the VNC
#    pointer). Run the leg with:  charly check live $IMG --filter cdp --filter vnc
#    Full recipe: /charly-check:cdp.

# 4. Verify completion from a structured snapshot or durable transcript.
charly agent terminal snapshot "$PROFILE" --target "$TARGET" --run-id "$RUN"
# Should show: "OpenAI OAuth complete", "Default model set to openai-codex/gpt-5.4"
```

**Prerequisites:** Chrome must have an active Google session. The "Continue with Google" button on OpenAI's auth page uses Chrome's Google cookies — sign Chrome into Google (with sync enabled) via the VNC desktop before starting the OAuth flow.

**Callback architecture:** The OAuth callback hits `http://127.0.0.1:1455/auth/callback` inside the container. Chrome and `openclaw-models` share the same network namespace — no port mapping needed for 1455. The `BROWSER=browser-open` env var (set by the chrome candy) auto-opens URLs via CDP, but may not trigger in all TTY contexts — author a `cdp: open` step (the `cdp:` verb, served out-of-process by candy/plugin-cdp) as a fallback.

**Stale port 1455:** If a previous attempt left port 1455 occupied, kill the stale holder: `charly shell $IMG -c 'kill -9 $(ss -tlnp sport = :1455 | grep -oP "pid=\K\d+")'`. If the surviving owner is a live agent run, treat it as an incident instead (per R1): preserve its terminal/process evidence, complete RCA, and apply an explicit recovery decision.

Tokens persist in `~/.openclaw/agents/main/agent/auth-profiles.json` in the `data` volume. Survive `charly stop`/`charly start` and image rebuilds. Only destroyed by `charly remove --purge`.

Model name: `openai-codex/gpt-5.4`. The `--set-default` flag sets it as the default model in `openclaw.json`.

### Checking Model Status

```bash
openclaw models status
# Shows: provider, model, auth profiles, token expiry, usage quotas
```

### Model Failover

Two-stage failure handling:
1. **Auth profile rotation**: cycles credentials for current provider
2. **Model fallback**: switches to next model in fallback chain

Backoff: 1min -> 5min -> 25min -> 1hr (capped). Auth profiles pin per session and reset on `/new` or compaction.

### Custom Providers

```json5
models: {
  providers: {
    "my-local": {
      baseUrl: "http://localhost:4000/v1",
      api: "openai-completions",
      models: [{ id: "my-model", contextWindow: 128000, maxTokens: 32000 }]
    }
  }
}
```

## Browser Integration

### Connecting to Existing Chrome

In a composed openclaw desktop box (e.g. `openclaw-desktop`), Chrome already runs as a supervisord service on port 9222. OpenClaw must connect to it rather than launching a new instance:

```bash
openclaw config set browser.cdpUrl "http://127.0.0.1:9222"
supervisorctl restart openclaw
```

Do **not** use `openclaw browser start` in this box -- it attempts to launch a separate Chrome instance that fails without Wayland environment variables.

After configuration, verify:

```bash
openclaw browser status    # Should show running: true, cdpPort: 9222
openclaw browser tabs      # Lists open Chrome tabs
```

### Browser Commands

```bash
openclaw browser open https://example.com        # Open URL in new tab
openclaw browser navigate https://other.com       # Navigate current tab
openclaw browser snapshot                          # AI-accessible page structure
openclaw browser snapshot --format aria            # Accessibility tree
openclaw browser screenshot                        # PNG to media dir
openclaw browser screenshot --full-page            # Full page capture
openclaw browser click 12                          # Click element by AI ref
openclaw browser type 23 "hello" --submit          # Type + submit
openclaw browser press Enter                       # Key press
openclaw browser hover 44                          # Hover element
openclaw browser fill --fields '[{"ref":"1","value":"Ada"}]'
openclaw browser wait --text "Done"                # Wait for text
openclaw browser wait --url "**/dashboard"         # Wait for URL pattern
openclaw browser evaluate --fn '(el) => el.textContent' --ref 7
openclaw browser console --level error             # Console messages
openclaw browser cookies                           # Read cookies
openclaw browser pdf                               # Save page as PDF
```

### Snapshot System

Snapshots provide element references for interaction:
- **AI snapshot** (default): numeric refs (`click 12`, `type 23 "text"`)
- **Role snapshot** (`--interactive`): e-prefixed refs (`click e12`)
- **Efficient preset** (`--efficient`): compact + interactive + depth reduction
- Refs reset after navigation -- always re-snapshot before interacting

### Browser Profiles

```json5
browser: {
  profiles: {
    openclaw: { cdpPort: 18800 },                           // managed (default)
    user: { driver: "existing-session", attachOnly: true },  // attach to running Chrome
    remote: { cdpUrl: "http://10.0.0.42:9222" },            // remote CDP
    cloud: { cdpUrl: "wss://connect.browserbase.com?apiKey=<KEY>" }
  }
}
```

## Agent Configuration

### Defaults

```json5
agents: {
  defaults: {
    workspace: "~/.openclaw/workspace",
    maxConcurrent: 4,
    compaction: { mode: "safeguard" },
    subagents: { maxConcurrent: 8, maxChildrenPerAgent: 5, maxSpawnDepth: 1 },
    tools: { profile: "coding" },     // coding|minimal|messaging|full
    elevatedDefault: "off"             // off|on|ask|full
  }
}
```

### Bootstrap Files

Placed in the agent workspace, injected on first session turn:
- `AGENTS.md` -- operating instructions and memory
- `SOUL.md` -- persona, boundaries, tone
- `TOOLS.md` -- user-maintained tool documentation
- `IDENTITY.md` -- agent name and characteristics

### Multi-Agent Routing

```json5
agents: {
  list: [
    { id: "main", default: true, name: "Main", model: "openai-codex/gpt-5.4" },
    { id: "home", name: "Home Assistant", model: "anthropic/claude-sonnet-4-5" }
  ],
  bindings: [
    { agentId: "home", match: { channel: "telegram", peer: { id: "123" } } }
  ]
}
```

## Channel Setup

### Supported Channels

WhatsApp, Telegram, Discord, Slack, Signal, Google Chat, Mattermost, iMessage, IRC, Microsoft Teams, BlueBubbles.

### DM Policies

| Policy | Description |
|--------|-------------|
| `pairing` | Unknown senders get approval code (default) |
| `allowlist` | Only pre-approved senders |
| `open` | Accept all (requires `allowFrom: ["*"]`) |
| `disabled` | Ignore all DMs |

### Quick Channel Setup

```bash
# Connect WhatsApp (QR code linking)
openclaw channels login --channel whatsapp

# Connect Telegram (requires bot token from BotFather)
openclaw config set channels.telegram.botToken "BOT_TOKEN"
openclaw channels login --channel telegram

# Connect Discord (requires bot token)
openclaw config set channels.discord.token "BOT_TOKEN"

# Check channel status
openclaw channels status --probe
```

## Key Config Paths

| Path | Purpose |
|------|---------|
| `~/.openclaw/openclaw.json` | Main config (JSON5) |
| `~/.openclaw/agents/<id>/agent/auth-profiles.json` | Model auth tokens |
| `~/.openclaw/agents/<id>/sessions/` | Session data |
| `~/.openclaw/workspace/` | Agent workspace |
| `~/.openclaw/media/browser/` | Browser screenshots |
| `~/.openclaw/logs/` | Audit logs |
| `/tmp/openclaw/openclaw-YYYY-MM-DD.log` | Gateway runtime log |

## Troubleshooting

### Gateway won't start

Check supervisord: `supervisorctl status openclaw`. If cycling between STARTING and STOPPED:

```bash
# Run manually to see error output
supervisorctl stop openclaw
timeout 15 openclaw gateway --port 18789
```

Common fixes:
- `gateway.mode` not set -> `openclaw config set gateway.mode local`
- Control UI origin error -> The gateway uses port_relay (socat) to bind to loopback, avoiding origin checks. If you see `allowedOrigins` errors, verify the relay is running: `supervisorctl status relay-18789`

### Browser not connected

If `openclaw browser status` shows `running: false`:

```bash
openclaw config set browser.cdpUrl "http://127.0.0.1:9222"
supervisorctl restart openclaw
```

### OAuth flow

Use `--tty` for the interactive CLI. The `BROWSER=browser-open` env var auto-opens OAuth URLs in Chrome. The callback URL (`http://127.0.0.1:1455/auth/callback`) is container-internal and needs no port mapping.

```bash
charly shell <image> --tty -c "openclaw models auth login --provider openai-codex --set-default"
```

For browser-assisted OAuth (Google sign-in), see `/charly-check:cdp`.

### First-run gateway setup (complete sequence)

After the first container start, configure the gateway:

```bash
charly shell <image> -c "openclaw config set gateway.mode local"
charly shell <image> -c "openclaw config set browser.cdpUrl 'http://127.0.0.1:9222'"
charly shell <image> -c "supervisorctl restart openclaw"
```

## Cross-References

- `/charly-check:cdp` -- the `cdp:` check verb (Chrome DevTools Protocol automation, served out-of-process by candy/plugin-cdp)
- `/charly-core:deploy` -- Quadlet, tunnels, volume backing, VNC password
- `/charly-core:service` -- `charly start/stop/enable/disable/status/logs/update/remove`
- `/charly-check:vnc` -- VNC desktop automation and password management
- `/charly-automation:alias` -- Host command aliases (`charly alias add openclaw`)
- `/charly-core:shell` -- `charly shell --tty` for interactive container commands

## When to Use This Skill

**MUST be invoked** when the task involves OpenClaw gateway configuration, model auth, browser integration, channel setup, or openclaw boxes. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Post-deployment. Configure the gateway after the container is running. See also `/charly-openclaw:openclaw*` (box variants).
