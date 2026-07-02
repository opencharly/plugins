---
name: stop
description: |
  Stop a running service container.
  MUST be invoked before any work involving: charly stop command, stopping containers, or halting services.
---

# charly stop -- Stop Service Container

## Overview

Stops a running service container. In quadlet mode, stops the systemd user service. In direct mode, stops the container via the container engine.

**Relationship to `charly bundle del`** — `charly stop <name>` is the ergonomic wrapper for `charly bundle del <name>` on a container deploy. The two are interchangeable for container deploys; `charly bundle del host` is required for the host-target teardown path (which runs ReverseOps, removes env.d files, and strips the shell managed block). See `/charly-core:deploy` and `/charly-local:local-deploy`.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Stop service | `charly stop <image>` | Stop the running container |
| With instance | `charly stop <image> -i 2` | Stop a specific instance |
| Stop + tear down FUSE | `charly stop <image> --unmount` | Stop the container AND unmount encrypted volumes (drops `charly-enc-<image>-<volume>.scope` units) |

## Usage

```bash
# Stop a running service
charly stop jupyter

# Stop a specific instance
charly stop ollama -i 2

# Stop and tear down encrypted FUSE mounts in one step
charly stop immich --unmount
```

## Flags

| Flag | Description |
|------|-------------|
| `-i, --instance INSTANCE` | Target a specific container instance |
| `--unmount` | After the container stop succeeds, also tear down `charly-enc-<image>-<volume>.scope` units via `encUnmount`. Best-effort: per-volume unmount failures emit a warning but don't propagate (the container has already stopped; the user can retry with `charly config unmount <image>`). Default `false` — plain `charly stop` leaves gocryptfs scopes running so they survive container restart (the original load-bearing design from `/charly-automation:enc`). |

## Behavior

- **Quadlet mode:** Runs `systemctl --user stop charly-<image>.service`
- **Direct mode:** Runs `<engine> stop <container>`
- Does not remove the container or its configuration -- use `charly remove` for that
- Does not disable the service -- the container may restart on next login if enabled
- To stop and disable: `charly start <image> --enable=false` then `charly stop <image>`
- **By design**, plain `charly stop` does NOT tear down encrypted FUSE mounts — the `charly-enc-*.scope` units are deliberately decoupled from the container service cgroup so they survive `KillMode=mixed` on stop and let the next start fast-path through the `charly config mount` short-circuit. Use `--unmount` for the full teardown semantics.

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:start` -- Start services
- `/charly-core:remove` -- Remove containers, quadlets, and deploy config
- `/charly-core:charly-status` -- Check service status
