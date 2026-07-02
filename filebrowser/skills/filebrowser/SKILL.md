---
name: filebrowser
description: |
  FileBrowser Quantum web file manager with Tailscale tunnel.
  MUST be invoked before building, deploying, configuring, or troubleshooting the filebrowser box.
---

# filebrowser

Web file manager accessible via Tailscale private tunnel.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | agent-forwarding, filebrowser, dbus, charly |
| Platforms | linux/amd64 |
| Ports | 8085:8080 |
| Tunnel | tailscale (private: all) |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` (base)
2. `pixi` -> `python` -> `supervisord` (transitive)
3. `agent-forwarding` -- SSH/GPG agent forwarding
4. `filebrowser` -- web file manager, data + files volumes
5. `dbus` -- D-Bus session bus
6. `charly` -- charly CLI inside container

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 8085 (host) -> 8080 (container) | FileBrowser | HTTP |

## Volumes

| Name | Path | Purpose |
|------|------|---------|
| data | ~/.filebrowser/data | Database (SQLite) and cache |
| files | ~/.filebrowser/files | User-accessible files (bind-mount target) |

## Quick Start

```bash
charly box build filebrowser
charly config filebrowser --bind files=~/Documents
charly start filebrowser
# Access at http://localhost:8085
# Tailscale: https://<hostname>:8085
# Default login: admin / admin
```

## Bind Mount Examples

```bash
# Browse home directory
charly config filebrowser --bind files=~/

# Browse NAS mount
charly config filebrowser --bind files=/mnt/nas/shared

# Browse specific project
charly config filebrowser --bind files=~/projects
```

## Host Alias

```bash
charly alias install filebrowser
# Now: filebrowser  (runs inside the container)
```

## Key Candies

- `/charly-filebrowser:filebrowser` -- FileBrowser Quantum service, config, volumes
- `/charly-distros:agent-forwarding` -- SSH/GPG agent forwarding
- `/charly-infrastructure:dbus-layer` -- D-Bus session bus
- `/charly-tools:charly` -- charly CLI for in-container management

## Related Boxes

- `/charly-distros:fedora` -- parent base image
- `/charly-ollama:ollama` -- similar simple service pattern

## Verification

After `charly start`:
- `charly status filebrowser` -- container running
- `curl -s http://localhost:8085` -- web UI responds (HTTP 200)
- `curl -s http://localhost:8085/health` -- `{"message":"ok"}`
- Tailscale: `https://<hostname>:8085` from any tailnet device

## Test Coverage

Latest `charly check live filebrowser` run: **24 passed, 0 failed, 0 skipped**.
All scenario steps embedded in the `ai.opencharly.description` OCI label, covering
agent-forwarding prerequisites (gpg, ssh, direnv binaries), supervisord
+ dbus daemon + charly binary presence, filebrowser binary + config, and
`context: [deploy]` steps: service up, port reachable on `127.0.0.1:${HOST_PORT:8080}`,
HTTP 200 on `/`, data volume mounted.

See `/charly-check:check` for the framework and author-facing gotchas.

## Related Skills

- `/charly-filebrowser:filebrowser` — candy authoring
- `/charly-check:check` — declarative testing framework
- `/charly-core:charly-config` — deploy-mode setup with volume backing and tunnels
- `/charly-build:build` — LABELs-at-end cache efficiency

## When to Use This Skill

**MUST be invoked** when the task involves the filebrowser box, web file management deployment, or the FileBrowser Quantum service. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
