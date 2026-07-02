---
name: cmd
description: |
  Single command execution in a running container with D-Bus notification.
  MUST be invoked before any work involving: charly cmd command, running commands in containers, or container exec with notifications.
---

# charly cmd -- Single Command Execution

## Overview

Runs a single command inside a running container via `<engine> exec` and sends a D-Bus desktop notification when the command completes. Useful for one-off commands without opening an interactive shell.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Run command | `charly cmd <image> "command"` | Execute command in running container |
| With instance | `charly cmd <image> "command" -i 2` | Target specific instance |
| With env vars | `charly cmd <image> "command" -e KEY=VALUE` | Pass environment variables |

## Usage

```bash
# Run a command in a running container
charly cmd fedora "uname -a"

# Run with environment variables
charly cmd jupyter "python script.py" -e CUDA_VISIBLE_DEVICES=0

# Target a specific instance
charly cmd ollama "ollama list" -i 2
```

## Flags

| Flag | Description |
|------|-------------|
| `-i, --instance INSTANCE` | Target a specific container instance (default: 1) |
| `-e, --env KEY=VALUE` | Pass environment variables to the command |
| `--sidecar NAME` | Run in the named SIDECAR container (`charly-<box>[-<inst>]-<name>`) instead of the app container |

## Behavior

- The container must already be running (`charly start <image>`)
- Agent forwarding (SSH/GPG) env vars are injected automatically if enabled
- A D-Bus desktop notification is sent on command completion (success or failure)
- For interactive shells, use `charly shell` instead
- For persistent sessions or long-running commands, use `charly tmux cmd`

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:shell` -- Interactive shell sessions with workspace mounts
- `/charly-check:dbus` -- D-Bus interaction inside containers
- `/charly-automation:tmux` -- Persistent tmux sessions for long-running commands
