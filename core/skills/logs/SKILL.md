---
name: logs
description: |
  Service log viewing for running containers.
  MUST be invoked before any work involving: charly logs command, viewing container output, or debugging service issues.
---

# charly logs -- Service Log Viewing

## Overview

Displays logs from a running or recently stopped service container. In quadlet mode, reads from journalctl. In direct mode, reads from the container engine's log store.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| View logs | `charly logs <image>` | Show recent logs |
| Follow logs | `charly logs <image> -f` | Stream logs in real time |
| Tail N lines | `charly logs <image> -n 50` | Show last N lines |
| With instance | `charly logs <image> -i 2` | Logs from specific instance |

## Usage

```bash
# View recent logs
charly logs jupyter

# Follow logs in real time (Ctrl+C to stop)
charly logs ollama -f

# Show last 100 lines
charly logs immich -n 100

# Logs from a specific instance
charly logs openclaw -i 2

# Combine follow with tail
charly logs comfyui -f -n 50
```

## Flags

| Flag | Description |
|------|-------------|
| `-f, --follow` | Stream logs continuously |
| `-n, --lines LINES` | Number of recent lines to show |
| `-i, --instance INSTANCE` | Target a specific container instance |
| `--sidecar NAME` | Show the named SIDECAR container's logs instead of the app container's |

## Behavior

- **Quadlet mode:** Uses `journalctl --user -u charly-<image>.service`
- **Direct mode:** Uses `<engine> logs <container>`
- Quadlet mode is the default and recommended deployment method
- Logs include both stdout and stderr from the container

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:charly-status` -- Check service status
- `/charly-core:service` -- Service lifecycle management
- `/charly-core:start` -- Starting services
