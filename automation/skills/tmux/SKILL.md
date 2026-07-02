---
name: tmux
description: |
  Persistent tmux sessions inside containers: shell reconnection, background commands,
  output capture, and key sending. Use when running long-lived or TTY-dependent commands.
  MUST be invoked before any work involving: charly tmux commands, persistent shells,
  background container commands, or TTY-dependent TUI programs.
---

# Tmux - Persistent Sessions Inside Containers

## Overview

`charly tmux` manages tmux sessions inside running containers. It solves two problems:

1. **Persistent shells** — SSH drops, terminal closes, network interruption? Just run `charly tmux shell <image>` again and you're back where you left off.
2. **TTY-dependent background commands** — TUI programs like `openclaw models auth login` need a real terminal to function. `charly shell --tty` piped through `tee` or redirected breaks the TUI event loop. `charly tmux run` provides a real tmux terminal that the TUI can use, while `charly tmux capture` reads the output without attaching.

All operations translate to `engine exec container tmux <args>`. The tmux candy must be present in the box (`candy/tmux/charly.yml` — installs the `tmux` RPM).

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Persistent shell | `charly tmux shell <image>` | Create or reattach to a shell session |
| Send command | `charly tmux cmd <image> "command" -s <name>` | Send command to session (with notification) |
| Run detached | `charly tmux run <image> -s <name> "<command>"` | Start command in new detached session |
| Attach | `charly tmux attach <image> -s <name>` | Attach to session interactively |
| List sessions | `charly tmux list <image>` | Show active tmux sessions |
| Capture output | `charly tmux capture <image> -s <name>` | Print pane output (for automation) |
| Send keys | `charly tmux send <image> -s <name> "text" --enter` | Send keystrokes to session |
| Kill session | `charly tmux kill <image> -s <name>` | Kill a tmux session |

All commands accept `-i INSTANCE` for multi-instance support.

## Commands

### `charly tmux shell` — Persistent Shell

The user-friendly entry point. Creates or reattaches to a persistent shell session.

```bash
# First call creates a "shell" session and attaches
charly tmux shell sway-browser-vnc

# After detaching (Ctrl-b d) or disconnect, reattach:
charly tmux shell sway-browser-vnc
# → Picks up right where you left off

# Use a custom session name:
charly tmux shell sway-browser-vnc -s dev
```

**Behavior:**
- If session exists → `tmux attach-session -t <name>`
- If not → `tmux new-session -s <name>` (creates with bash)
- Always interactive — uses `syscall.Exec` with `-it` for a real terminal
- Default session name: `shell`
- Detach with **Ctrl-b d** (standard tmux detach)

### `charly tmux cmd` — Send Command to Session

Sends a command (text + Enter) to an existing tmux session. Returns immediately after sending. Sends a desktop notification by default (disable with `--no-notify`).

```bash
charly tmux cmd sway-browser-vnc "ls -la" -s oauth
charly tmux cmd jupyter "python train.py" -s training --no-notify
```

**Behavior:**
- Sends literal text followed by Enter key to the named session
- Errors if session doesn't exist (use `charly tmux list` to see sessions)
- Desktop notification sent when command is dispatched (requires swaync/mako daemon)
- Convenience wrapper for `charly tmux send <image> -s <name> -l "command" --enter`

### `charly tmux run` — Detached Command

Starts a command in a new named tmux session. Returns immediately — the command runs in the background with a real TTY.

```bash
# Run OAuth flow in background with real terminal
charly tmux run sway-browser-vnc -s oauth \
  "openclaw models auth login --provider openai-codex --set-default"

# Run any long-lived command
charly tmux run jupyter -s training "python train.py --epochs 100"
```

**Behavior:**
- Non-interactive — uses `exec.Command`, returns immediately
- Creates session with `-d` (detached)
- Errors if session name already exists
- The command runs inside a real tmux PTY — TUI programs work correctly

### `charly tmux attach` — Interactive Attach

Attaches to an existing session. Use when you want to interact with a running command.

```bash
charly tmux attach sway-browser-vnc -s oauth
# Detach with Ctrl-b d
```

**Behavior:**
- Interactive — `syscall.Exec` replaces the process
- Errors if session not found (use `charly tmux list` to see sessions)

### `charly tmux list` — List Sessions

```bash
charly tmux list sway-browser-vnc
# shell: 1 windows (created Sat Mar 21 16:54:15 2026)
# oauth: 1 windows (created Sat Mar 21 17:01:22 2026)
```

No sessions is not an error — prints an informational message.

### `charly tmux capture` — Read Output

Reads the current pane content without attaching. Essential for automation — Claude Code and scripts can check on running commands.

```bash
# Read visible pane content
charly tmux capture sway-browser-vnc -s oauth

# Read last 50 lines of history
charly tmux capture sway-browser-vnc -s oauth -n 50
```

**Flags:**
- `-n <lines>` — Number of history lines (0 = visible pane only, default)

### `charly tmux send` — Send Keys

Sends keystrokes to a running session. For automation when you need to respond to prompts.

```bash
# Type text and press Enter
charly tmux send sway-browser-vnc -s oauth "yes" --enter

# Send literal text (disable tmux key name interpretation)
charly tmux send sway-browser-vnc -s oauth -l "C-c is not ctrl-c here"

# Send special keys
charly tmux send sway-browser-vnc -s oauth Enter
charly tmux send sway-browser-vnc -s oauth C-c
```

**Flags:**
- `--enter` — Append Enter key after the text
- `-l` / `--literal` — Send keys literally (disable key name lookup)

### `charly tmux kill` — Kill Session

```bash
charly tmux kill sway-browser-vnc -s oauth
# Killed tmux session "oauth" in charly-sway-browser-vnc
```

## Use Case: OpenAI Codex OAuth

The primary use case that motivated `charly tmux`. The `openclaw models auth login` TUI requires a real terminal to complete the post-callback token exchange. `charly shell --tty` piped through `tee` or backgrounded breaks the TUI event loop — the callback is received but tokens are never saved.

```bash
IMG=sway-browser-vnc

# 1. Start OAuth in a tmux session (real terminal)
charly tmux run $IMG -s oauth \
  "openclaw models auth login --provider openai-codex --set-default"

# 2. Read the OAuth URL from tmux output
charly tmux capture $IMG -s oauth | grep -o 'https://auth.openai.com/[^ ]*'

# 3. Drive the browser via cdp:/vnc: plan steps (the cdp: verb is served
#    out-of-process by candy/plugin-cdp): cdp: open the OAuth URL, then locate
#    "Continue with Google" / "Continue" (consent) with cdp: coords on
#    'button._buttonStyleFix_wvuha_65' / 'button._primary_3rdp0_107' and deliver
#    each click via the vnc: verb. Run the leg with:
#    charly check live $IMG --filter cdp --filter vnc   (full recipe: /charly-check:cdp)

# 4. Verify token exchange completed
sleep 10
charly tmux capture $IMG -s oauth | tail -5
# Should show: "OpenAI OAuth complete", "Default model set to openai-codex/gpt-5.4"

# 5. Clean up
charly tmux kill $IMG -s oauth
```

## Use Case: Persistent Development Shell

```bash
# Start a shell that survives disconnects
charly tmux shell jupyter

# Work inside the shell...
# pip install something, edit configs, run scripts

# Connection drops or terminal closes
# Just reconnect:
charly tmux shell jupyter
# → Everything is still there
```

## Prerequisites

The `tmux` candy must be included in the box. Check with:

```bash
charly shell <image> -c "which tmux"
```

If tmux is not installed, `charly tmux` returns: `"tmux is not installed in container <name> (add the tmux layer to your image)"`.

The tmux candy is already a dependency of `openclaw-full` (and all derivative boxes). For other boxes, add `tmux` to the candies list in `charly.yml`.

## tmux Basics

For users unfamiliar with tmux:

| Key | Action |
|-----|--------|
| `Ctrl-b d` | Detach from session (leaves it running) |
| `Ctrl-b [` | Enter scroll mode (navigate with arrows, q to exit) |
| `Ctrl-b c` | Create new window |
| `Ctrl-b n` / `Ctrl-b p` | Next / previous window |
| `Ctrl-b %` | Split pane vertically |
| `Ctrl-b "` | Split pane horizontally |

## Naming Consistency

Command execution follows a consistent naming pattern across charly:

| Interactive shell | Single command | Persistent session |
|-------------------|---------------|-------------------|
| `charly shell` | `charly cmd` | — |
| `charly tmux shell` | `charly tmux cmd` | `charly tmux run` |

- `charly cmd` — runs command synchronously in running container, notifies on completion
- `charly tmux cmd` — sends command to existing tmux session, notifies on dispatch
- `charly tmux run` — creates new detached tmux session with command

## Cross-References

- `charly cmd` — Single command execution with D-Bus notification (running containers only, no tmux)
- `/charly-core:shell` — `charly shell` for one-shot commands (no persistence) or `charly shell -c` (full container setup)
- `/charly-check:cdp` — Chrome DevTools Protocol (used with tmux for OAuth flows)
- `/charly-automation:openclaw-deploy` — OpenClaw gateway config (OAuth requires tmux for token exchange)
- `/charly-core:service` — Supervisord service management (different scope: persistent services vs ad-hoc commands)
- `/charly-infrastructure:tmux-layer` — The tmux candy definition
- `/charly-infrastructure:dbus-layer` — D-Bus session bus (required for notifications)

## When to Use This Skill

**MUST be invoked** when the task involves:

- Running long-lived commands inside containers
- TTY-dependent TUI programs (OAuth flows, interactive installers)
- Persistent shells that survive disconnects
- Background commands with output monitoring
- Sending keystrokes to running programs
- "How do I run a command that needs a real terminal?"
- "How do I reconnect to a container shell after disconnect?"
- "How do I run openclaw auth login in the background?"
