---
name: openwebui
description: |
  Open WebUI box with auto-configured LLM providers, MCP servers, and Jupyter on port 8080.
  MUST be invoked before building, deploying, configuring, or troubleshooting the openwebui box.
---

# Box: openwebui

Open WebUI with auto-configured LLM providers (Ollama, OpenRouter), MCP server discovery, and Jupyter code execution. No manual setup needed — secrets auto-managed via `charly secrets`.

## Definition

```yaml
openwebui:
  base: fedora
  candy:
    - agent-forwarding
    - openwebui
    - dbus
    - charly
  ports:
    - "8080:8080"
```

## Candy Stack

| Candy | Purpose |
|-------|---------|
| `agent-forwarding` | SSH + GPG agent forwarding into container |
| `openwebui` | Open WebUI with auto-config entrypoint |
| `dbus` | D-Bus session bus |
| `charly` | OpenCharly CLI for in-container management |

## Quick Start

```bash
charly box build openwebui
charly config openwebui -e OPENROUTER_API_KEY=sk-or-xxx
charly start openwebui
# Open http://localhost:8080
```

## Deployment Patterns

### Standalone with GPG secrets (recommended)
```bash
charly secrets gpg setup
charly secrets gpg set OPENROUTER_API_KEY sk-or-xxx
charly box build openwebui
charly config openwebui --env-file .secrets
charly start openwebui
```

### With local Ollama
```bash
charly config ollama
charly config openwebui --env-file .secrets --update-all
charly start ollama openwebui
```

### Full workstation (Ollama + Jupyter + Browser)
```bash
charly config ollama
charly config jupyter --update-all
charly config selkies-desktop --update-all
charly config openwebui --env-file .secrets --update-all
charly start ollama jupyter selkies-desktop openwebui
```

## Secrets Management

```bash
# Tier 1: Auto-generated infrastructure secrets
charly secrets list charly/openwebui
charly secrets get charly/openwebui webui-secret-key
charly secrets set charly/openwebui admin-password --generate

# Tier 2: User API keys (GPG-encrypted)
charly secrets gpg set OPENROUTER_API_KEY sk-or-new-key
charly secrets gpg show
charly config openwebui --env-file .secrets --update-all
```

## Cross-Container Service Discovery

Deploy alongside provider containers for full functionality:

```bash
# 1. Deploy ollama (provides OLLAMA_HOST)
charly config ollama
charly start ollama

# 2. Deploy jupyter (provides jupyter MCP server)
charly config jupyter --update-all
charly start jupyter

# 3. Deploy openwebui (consumes both)
charly config openwebui --env-file .secrets --update-all
charly start openwebui
```

Open WebUI receives:
- `OLLAMA_BASE_URL=http://charly-ollama:11434` — local LLM inference
- `TOOL_SERVER_CONNECTIONS=[...]` — MCP servers (jupyter + chrome-devtools)
- `CODE_EXECUTION_ENGINE=jupyter` — code execution via Jupyter

## Key Candies

- `/charly-openwebui:openwebui` — Auto-config entrypoint, secrets, env_accept, TOOL_SERVER_CONNECTIONS format
- `/charly-distros:agent-forwarding` — SSH/GPG forwarding

## Related Boxes

- `/charly-jupyter:jupyter` — deploy alongside for MCP notebooks and code execution
- `/charly-ollama:ollama` — deploy alongside for local LLM inference
- `/charly-hermes:hermes` — alternative AI frontend (CLI agent vs web UI)
- `/charly-selkies:selkies-labwc` — deploy alongside for shared Chrome browser

## Verification

```bash
charly status openwebui
charly service status openwebui                    # openwebui: RUNNING
curl -s -o /dev/null -w '%{http_code}' http://localhost:8080   # 200
charly shell openwebui -c "open-webui version"

# Verify secrets
charly status openwebui   # the Secrets: line lists the provisioned charly-openwebui-* engine secrets              # webui-secret-key, admin-password

# Verify MCP (inside container process)
charly cmd openwebui "cat /proc/3/environ" | tr '\0' '\n' | grep TOOL_SERVER_CONNECTIONS
```

## Test Coverage

Latest `charly check live openwebui` run: **24 passed, 0 failed, 0 skipped**.
Covers: openwebui entrypoint script presence, pixi python + charly binary,
and deploy-scope: service up, port reachable on `127.0.0.1:${HOST_PORT:8080}`,
HTTP 200 on `/` (30-second timeout for first-request startup), admin
email env var injected. See `/charly-check:check` for the framework.

## Related Skills

- `/charly-openwebui:openwebui` — candy authoring
- `/charly-check:check` — declarative testing framework
- `/charly-build:secrets` — WEBUI_ADMIN_PASSWORD + provider API keys
- `/charly-core:charly-config` — `-e WEBUI_ADMIN_EMAIL=...` deploy-time env setup

## When to Use This Skill

**MUST be invoked** before building, deploying, configuring, or troubleshooting the openwebui box.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
