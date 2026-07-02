---
name: waybar-labwc
description: |
  Waybar status bar adapted for the labwc compositor (not sway) — shares the unified waybar config and connects to labwc's wayland-0 socket for layer-shell exclusive zones and the wlr-foreign-toplevel taskbar.
  Use when working with the labwc status bar or the selkies-desktop waybar.
---

# Candy: waybar-labwc

Waybar status bar adapted for labwc compositor (not sway). Uses the same unified config as the `waybar` candy — sway-specific modules (workspaces, mode) auto-hide on labwc since `SWAYSOCK` is not set.

## Architecture

Waybar connects to `wayland-0` (labwc's socket), NOT `wayland-1` (pixelflux). This is critical for:
- **Layer-shell exclusive zones** — Waybar reserves space at the top, windows don't overlap it
- **wlr-foreign-toplevel-management** — Waybar's taskbar can see running windows in labwc

## Dependencies

- `labwc`

## Packages

- `waybar` (RPM)

Fonts (JetBrains Mono, Symbols Nerd Font) provided by the `desktop-fonts` candy in metalayers.

## Service (supervisord)

| Service | Priority | Purpose |
|---------|----------|---------|
| `waybar` | 15 | Bottom panel (after labwc at 12, swaync at 14, before nginx at 18) |

## Configuration

Unified config shared with the `waybar` candy (Catppuccin Mocha, bottom bar):

### Modules

| Position | Module | Purpose |
|----------|--------|---------|
| Left | `custom/chrome` | (Re)start Chrome button — calls `chrome-restart` (see `/charly-selkies:chrome`) |
| Center | `wlr/taskbar` | Running app icons — click to activate, middle-click to close, right-click to minimize |
| Right | `custom/notification` | swaync notification toggle — click to open notification panel (see `/charly-selkies:swaync`) |

### Style

Catppuccin Mocha theme — semi-transparent dark background, JetBrains Mono + Symbols Nerd Font.

## Key Files

- `waybar-labwc-wrapper` — Waits for `wayland-0` socket, sets `WAYLAND_DISPLAY=wayland-0` explicitly
- `config.json` — Unified module layout (same as waybar layer)
- `style.css` — Catppuccin Mocha styling (same as waybar layer)

## Used In Boxes

- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Note: Difference from `waybar` Layer

Both candies use the same config. The only differences are:
- **Dependency:** `labwc` instead of `sway`
- **Wrapper:** Explicitly pins `WAYLAND_DISPLAY=wayland-0` (labwc socket, not pixelflux's wayland-1)
- **No sway-autotile:** Autotiling is sway-specific

## Related

- `/charly-selkies:waybar` — the sway-native sibling with the same config
- `/charly-selkies:labwc` — compositor this candy targets
- `/charly-selkies:selkies-desktop-layer` — metalayer that composes this candy
- `/charly-selkies:swaync` + `/charly-selkies:chrome` — consumers of the status-bar modules

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
