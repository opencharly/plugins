---
name: alias
description: |
  MUST be invoked before any work involving: host command aliases, charly alias add/remove/install/uninstall, or wrapper scripts that run inside containers.
---

# Alias - Command Aliases

## Overview

`charly alias` creates distrobox-style wrapper scripts in `~/.local/bin/` that transparently run commands inside containers. Typing the alias name on the host executes the command inside the container via `charly shell`.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Install defaults | `charly alias install <image>` | Create wrappers from candy/box config |
| Uninstall all | `charly alias uninstall <image>` | Remove all wrappers for a box |
| Add manually | `charly alias add <name> <image> [command]` | Create a single wrapper |
| Remove one | `charly alias remove <name>` | Remove a single wrapper |
| List all | `charly alias list` | Show all installed aliases |

## How It Works

```bash
charly alias install openclaw     # Creates ~/.local/bin/openclaw
openclaw                      # Runs inside container transparently
charly alias uninstall openclaw   # Removes wrapper
```

### Wrapper Script Format

`charly alias add` / `charly alias install` writes shell scripts to `~/.local/bin/`:

```sh
#!/bin/sh
# charly-alias
# image: openclaw
# command: openclaw
_charly_q(){ printf "'"; printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf "' "; }
c="openclaw"; for a in "$@"; do c="$c $(_charly_q "$a")"; done
exec charly shell openclaw -c "$c"
```

Key details:
- The `# charly-alias` marker enables safe list/delete scanning
- `charly alias remove` verifies the marker before deleting
- The `_charly_q()` helper properly single-quotes each argument (POSIX sh compatible)
- Arguments are forwarded to `charly shell <image> -c "<command> <args>"`

## Declaration

### In a candy `charly.yml`

Candy aliases require both `name` and `command`. In the unified node-form each entity is name-first, and `alias` is a child node of the candy:

```yaml
ollama:
  candy:
    version: 2026.144.1531
    description: Ollama LLM runtime + CLI.
  ollama-alias:
    alias:
      - name: ollama
        command: ollama
      - name: ollama-run
        command: "ollama run"
```

### In a box `charly.yml`

Box-level aliases default `command` to `name` if omitted. Box-level aliases override candy aliases with the same name.

```yaml
my-app:
  candy:
    base: fedora
  my-app-alias:
    alias:
      - name: myapp          # command defaults to "myapp"
      - name: myctl
        command: "myapp ctl"
```

### Collection

`CollectImageAliases()` gathers aliases from the box's own candies (in dependency order) plus box-level config. **No base chain traversal** -- aliases are leaf-box specific (unlike volumes).

Source: `charly/alias.go`, `charly/layers.go` (`AliasYAML`, `HasAliases`, `Aliases()`).

## Commands

### Install All Aliases for a Box

```bash
charly alias install openclaw
# Created alias: openclaw -> openclaw (in openclaw)
```

Installs all aliases declared in the box's candies and box config.

### Uninstall All Aliases for a Box

```bash
charly alias uninstall openclaw
# Removed alias: openclaw
```

Removes all wrapper scripts that reference the box.

### Add a Single Alias

```bash
charly alias add mycommand my-image                   # command = mycommand
charly alias add mycommand my-image "custom command"   # explicit command
```

### Remove a Single Alias

```bash
charly alias remove mycommand
```

Only removes if the file contains the `# charly-alias` marker.

### List All Aliases

```bash
charly alias list
# NAME         IMAGE        COMMAND
# openclaw     openclaw     openclaw
# ollama       ollama       ollama
```

Scans `~/.local/bin/` for files with the `# charly-alias` marker.

## Validation Rules

- Candy aliases require both `name` and `command`
- Alias names must match `^[a-zA-Z0-9][a-zA-Z0-9._-]*$`
- Duplicate alias names within a box are errors
- Box-level alias `command` defaults to `name` if omitted

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:shell` -- How aliases execute commands via `charly shell -c`
- `/charly-image:layer` -- Declaring aliases in charly.yml
- `/charly-image:image` -- Box-level alias overrides

## When to Use This Skill

**MUST be invoked** when the task involves host command aliases, charly alias commands, or wrapper scripts that run inside containers. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Post-deployment. Use after a service is running to create host command shortcuts.
