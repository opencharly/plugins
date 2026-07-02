---
name: openclaw
description: |
  Headless OpenClaw AI gateway box. Runs the gateway on port 18789
  without a desktop environment. Use when working with the headless
  MUST be invoked before building, deploying, configuring, or troubleshooting the openclaw box.
---

# openclaw

Headless OpenClaw AI gateway — no desktop, no browser, just the gateway service.

## Box Properties

| Property | Value |
|----------|-------|
| Base | cachyos |
| Candies | agent-forwarding, openclaw, dbus, charly |
| Platforms | linux/amd64 |
| Ports | 18789 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `cachyos` (docker.io/cachyos/cachyos-v3, digest-pinned, Arch-derived)
2. `pixi` → `python` → `supervisord` (transitive)
3. `nodejs` (transitive via openclaw)
4. `openclaw` — gateway on :18789, data volume
5. `dbus` — message bus; `charly` — charly CLI toolchain

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 18789 | OpenClaw gateway + Control UI | HTTP |

## Quick Start

```bash
charly box build openclaw
charly config openclaw
charly start openclaw
# Gateway at http://localhost:18789
```

## Key Candies

- `/charly-openclaw:openclaw` — gateway npm package, supervisord service, data volume

## Related Boxes

- `/charly-openclaw:openclaw-full` — maximal variant (gateway + browser + all tools)

## Verification

After `charly start`:
- `charly status openclaw` — container running
- `charly service status openclaw` — all services RUNNING
- `curl -s http://localhost:18789` — OpenClaw gateway responds

## Port Relay Architecture

OpenClaw gateway (18789) uses port relay (socat) — the gateway binds to loopback, socat forwards from the container interface. This avoids the `allowedOrigins` requirement for the Control UI.

## When to Use This Skill

**MUST be invoked** when the task involves the headless openclaw box, deploying openclaw without a desktop, or comparing openclaw variants. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
