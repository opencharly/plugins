---
name: openclaw-layer
description: |
  OpenClaw AI gateway service on port 18789 via npm with persistent data.
  Use when working with OpenClaw, AI gateway configuration, or model routing.
---

# openclaw -- AI gateway service

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs`, `socat`, `supervisord` |
| Ports | 18789 |
| Port relay | 18789 (eth0 -> loopback) |
| Volumes | `data` -> `~/.openclaw` |
| Aliases | `openclaw` -> `openclaw` |
| Service | `openclaw` (supervisord) |
| Install files | `package.json` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `NODE_ENV` | `production` |

## Usage

```yaml
# charly.yml
openclaw:
  candy:
    - openclaw
```

```bash
charly alias install openclaw    # install host 'openclaw' command
openclaw config              # uses the alias
```

## Used In Boxes

- `/charly-openclaw:openclaw`
- `/charly-openclaw:openclaw-full`

## Port Relay

The gateway binds to `127.0.0.1:18789` (loopback only). A socat relay forwards from the container's network interface to loopback. This avoids OpenClaw's `allowedOrigins` requirement for the Control UI — all connections appear as loopback to the gateway.

Same pattern as the `chrome` candy (CDP on port 9222).

## Related Candies

- `/charly-coder:nodejs` -- Node.js runtime dependency
- `/charly-infrastructure:socat` -- port relay dependency (eth0 -> loopback)
- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-ollama:ollama` -- optional local LLM backend

## When to Use This Skill

Use when the user asks about:

- OpenClaw gateway setup or configuration
- AI model routing or gateway
- Port 18789 service
- The `openclaw` host alias
- OpenClaw data volume

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
