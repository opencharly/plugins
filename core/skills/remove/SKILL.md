---
name: remove
description: |
  Remove service container, quadlet file, and charly.yml entry.
  MUST be invoked before any work involving: charly remove command, cleaning up containers, removing quadlets, or purging volumes.
---

# charly remove -- Remove Service Container

## Overview

Removes a service container along with its quadlet file and charly.yml entry. Optionally purges named volumes and runs lifecycle hooks before removal.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Remove container | `charly remove <image>` | Remove container, quadlet, and deploy entry |
| Purge volumes | `charly remove <image> --purge` | Also remove named volumes |
| Keep deploy entry | `charly remove <image> --keep-deploy` | Keep charly.yml entry for re-configuration |
| With env vars | `charly remove <image> -e KEY=VALUE` | Pass env vars to pre_remove hooks |

## Usage

```bash
# Remove a service (container + quadlet + charly.yml entry)
charly remove jupyter

# Remove and purge all named volumes
charly remove ollama --purge

# Remove but keep charly.yml entry for later re-configuration
charly remove immich --keep-deploy

# Pass environment variables to pre_remove hooks
charly remove openclaw -e CLEANUP_MODE=full
```

## Flags

| Flag | Description |
|------|-------------|
| `--purge` | Also remove named volumes associated with the image |
| `--keep-deploy` | Preserve the charly.yml entry (useful for re-running `charly config`) |
| `-e, --env KEY=VALUE` | Pass environment variables to pre_remove lifecycle hooks |

## Behavior

1. Runs `pre_remove` lifecycle hooks (if defined in image labels)
2. Stops the container if still running
3. Removes the quadlet file (quadlet mode) or container (direct mode)
4. Removes the charly.yml entry (unless `--keep-deploy`)
5. With `--purge`: removes named volumes (`charly-<image>-<name>`)

## Lifecycle Hooks

Images can define `pre_remove` hooks that run before the container is removed. These are useful for graceful shutdown, data export, or cleanup tasks. Use `-e` to pass context to hooks.

## Instance Removal

Remove specific instances with `-i`:

```bash
charly remove selkies-desktop -i 192.241.92.221          # Remove instance
charly remove selkies-desktop -i 192.241.92.221 --purge  # Also purge volumes
```

Instance removal automatically cleans the instance's `env_provide` and `mcp_provide` from `charly.yml` provides section. Other instances of the same base image are unaffected.

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:stop` -- Stop without removing
- `/charly-core:charly-config` -- Configure/reconfigure services (see "Full instance removal" for 3-step cleanup)
- `/charly-core:deploy` -- Deploy.yml management, tunnel configuration
- `/charly-core:service` -- Full service lifecycle
- `/charly-build:charly-mcp-cmd` -- after `charly config remove` cleans this instance's `mcp_provide` from the global `provides.mcp:` list, consumers' `CHARLY_MCP_SERVERS` no longer lists it; use `charly check live <consumer> --filter mcp` to confirm the cleanup propagated
