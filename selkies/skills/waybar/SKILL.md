---
name: waybar
description: |
  Waybar status bar and sway-autotile for the Sway desktop compositor.
  Use when working with Waybar configuration, status bar, or automatic tiling.
---

# waybar -- Status bar and auto-tiling for Sway

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `sway` |
| Service | `waybar` (supervisord, priority 15), `sway-autotile` (priority 16) |
| Install files | `task:`, `config.json`, `style.css`, `waybar-wrapper`, `sway-autotile` |

## Packages

- `waybar` (RPM)

Fonts (JetBrains Mono, Symbols Nerd Font) provided by the `desktop-fonts` candy in metalayers.

## Configuration

Unified config shared with the `waybar-labwc` candy (Catppuccin Mocha, bottom bar):

### Modules

| Position | Module | Purpose |
|----------|--------|---------|
| Left | `custom/chrome` | (Re)start Chrome button — calls `chrome-restart` (see `/charly-selkies:chrome`) |
| Center | `wlr/taskbar` | Running app icons — click to activate, middle-click to close, right-click to minimize |
| Right | `custom/notification` | swaync notification toggle — click to open notification panel (see `/charly-selkies:swaync`) |

### Style

Catppuccin Mocha theme — semi-transparent dark background, JetBrains Mono + Symbols Nerd Font.

## Key Files

- `waybar-wrapper` — Waits for Wayland socket, discovers SWAYSOCK, then exec waybar
- `sway-autotile` — Subscribes to sway window events, auto-tiles windows restored from scratchpad
- `config.json` — Unified module layout (same as waybar-labwc candy)
- `style.css` — Catppuccin Mocha styling (same as waybar-labwc candy)

## Used In Boxes

Part of `/charly-selkies:sway-desktop` composition.

## Related Candies

- `/charly-selkies:sway` -- compositor dependency
- `/charly-selkies:sway-desktop` -- composition that includes waybar
- `/charly-selkies:swaync` -- notification daemon (notification bell module)
- `/charly-selkies:pavucontrol` -- volume control (pulseaudio on-click)
- `/charly-selkies:desktop-fonts` -- JetBrains Mono + Nerd Font icons

## Related Commands
- `/charly-check:wl` — interact with the Wayland session hosting waybar
- `/charly-core:shell` — restart waybar via supervisorctl

## When to Use This Skill

Use when the user asks about:

- Waybar configuration or styling
- Status bar in Sway desktop
- Automatic window tiling
- Desktop UI customization

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
