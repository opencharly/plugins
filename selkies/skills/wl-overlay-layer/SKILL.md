---
name: wl-overlay-layer
description: |
  Wayland overlay windows via gtk4-layer-shell (for screen recordings).
  Use when working with the wl-overlay candy, gtk4-layer-shell, or overlay dependencies.
---

# wl-overlay -- Wayland overlay windows via gtk4-layer-shell

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `dbus` |
| Install files | `task:`, `charly-overlay` |

## Packages

- `gtk4` (RPM)
- `gtk4-layer-shell` (RPM) — includes `Gtk4LayerShell-1.0.typelib` for GObject Introspection
- `python3-gobject` (RPM)

## Technical Details

### Python Script: `charly-overlay`

Installed to `~/.local/bin/charly-overlay` via `task:`. Dual-mode script (daemon + client) using GTK4 + gtk4-layer-shell for layer-shell protocol overlays.

**Key implementation details:**
- **Shebang**: `#!/usr/bin/python3` (system Python 3.14, NOT pixi's Python — PyGObject is an RPM package)
- **Library preload**: `CDLL("libgtk4-layer-shell.so.0")` must load before GTK4 import (registers layer-shell protocol before Wayland display init). Uses versioned soname `.so.0` (unversioned `.so` is in `-devel` package only)
- **RGBA surfaces**: `window { background: none; }` CSS applied globally at daemon startup. Without this, GTK4 on Wayland creates opaque surfaces that don't support alpha transparency
- **Cairo backgrounds**: all overlay backgrounds drawn via `Gtk.DrawingArea` + Cairo `paint()`. GTK4 CSS `background-color` with `rgba()` does not composite correctly on layer-shell windows
- **Thread safety**: socket listener runs in a separate thread; all GTK operations dispatched via `GLib.idle_add()`
- **IPC**: Unix domain socket at `/tmp/charly-overlay.sock` with JSON-line protocol

### Layer-Shell Configuration

- **Layer**: `OVERLAY` (above TOP where waybar/swaync live)
- **Keyboard mode**: `NONE` (overlays never capture input)
- **Exclusive zone**: `-1` (don't push other windows)
- **Namespace**: `charly-overlay-<name>` per overlay window

## Usage

```yaml
# charly.yml — typically included via desktop metalayers
# Already part of sway-desktop, selkies-desktop
my-desktop:
  candy:
    - wl-overlay
```

```yaml
overlay-show:
    check: a text overlay is shown on the desktop
    wl: overlay-show
    type: text
    text: Hello
    name: intro
    context: [deploy]

overlay-list:
    check: the active overlays are listed
    wl: overlay-list
    context: [deploy]

overlay-hide:
    check: all overlays are hidden
    wl: overlay-hide
    all: true
    context: [deploy]
```

## Used In

- `/charly-selkies:sway-desktop` — sway desktop composition
- `/charly-selkies:selkies-desktop-layer` — selkies streaming desktop composition

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Candies

- `/charly-infrastructure:dbus-layer` — D-Bus session bus (dependency, required by GTK4)
- `/charly-selkies:wl-tools` — Wayland automation tools (sibling in desktop stack)
- `/charly-selkies:a11y-tools` — also uses `python3-gobject` (RPM deduplication handles overlap)
- `/charly-infrastructure:tmux-layer` — tmux (required for overlay daemon hosting)

## Related Commands

- `/charly-check:wl-overlay` — Overlay command usage, types, recording workflow
- `/charly-check:wl` — Compositor-agnostic desktop automation
- `/charly-check:record` — Recording commands (overlays compose with recording)

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
