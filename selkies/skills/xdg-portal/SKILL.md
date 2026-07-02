---
name: xdg-portal
description: |
  XDG Desktop Portal infrastructure for Sway containers — the portal daemon, the wlroots backend (xdg-desktop-portal-wlr), and the GTK fallback — enabling screen sharing, portal screenshots, and file dialogs.
  Use when working with XDG desktop portals, screen-sharing, or file-dialog support inside a container.
---

# xdg-portal - XDG Desktop Portal Infrastructure

## Overview

Provides XDG Desktop Portal support for Sway containers. Installs the portal daemon, the wlroots-specific backend (`xdg-desktop-portal-wlr`), and the GTK fallback backend. Enables screen sharing, screenshots via portal API, and file dialogs for applications running inside the container.

## Candy Definition

```yaml
require:
  - dbus
  - sway
  - pipewire

env:
  XDG_CURRENT_DESKTOP: "sway"

rpm:
  packages:
    - xdg-desktop-portal
    - xdg-desktop-portal-wlr
    - xdg-desktop-portal-gtk
    - slurp
```

## Key Properties

| Property | Value |
|----------|-------|
| Depends | `dbus`, `sway`, `pipewire` |
| Packages | `xdg-desktop-portal`, `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gtk`, `slurp` |
| Env | `XDG_CURRENT_DESKTOP=sway` |
| Service | None (D-Bus activation on demand) |
| Ports | None |

## How It Works

1. **D-Bus activation:** Portal daemons start on-demand when an application calls a portal D-Bus method. No supervisord service needed.
2. **Sway config drop-in:** Installs `~/.config/sway/config.d/portal.conf` which runs `dbus-update-activation-environment` to export `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `XDG_CURRENT_DESKTOP`, and `SWAYSOCK` to the D-Bus activation environment. Without this, portal daemons can't find the Wayland display.
3. **Auto-approve config:** Installs `~/.config/xdg-desktop-portal-wlr/config` with `chooser_type=none` for headless automation (no user dialog for screen sharing).

## Portal Capabilities

| Interface | Backend | Status |
|-----------|---------|--------|
| Screenshot | xdg-desktop-portal-wlr | Supported |
| ScreenCast (PipeWire) | xdg-desktop-portal-wlr | Supported |
| RemoteDesktop | — | NOT supported on wlroots |
| File dialogs | xdg-desktop-portal-gtk | Supported (fallback) |
| Settings | xdg-desktop-portal-gtk | Supported (fallback) |

## Included In

- `sway-desktop` metalayer (default for all desktop boxes)

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)

## Cross-References

- `/charly-selkies:sway-desktop` — Desktop metalayer that includes this candy
- `/charly-infrastructure:dbus-layer` — D-Bus session bus (required dependency)
- `/charly-selkies:pipewire` — PipeWire (required for ScreenCast)
- `/charly-selkies:sway` — Sway compositor (required)

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
