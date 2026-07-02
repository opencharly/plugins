---
name: wl-tools
description: |
  Compositor-agnostic desktop automation CLI tools — Wayland-native input (wtype), X11, and clipboard (wl-clipboard) — that back the `wl:` check verb on wlroots compositors (sway, labwc) and partially on KWin.
  Use when working with the `wl:` check verb, Wayland desktop automation, keyboard/window control, or clipboard tooling.
---

# wl-tools - Compositor-Agnostic Desktop Automation Tools

## Overview

Provides CLI tools for desktop automation — Wayland-native, X11, and clipboard. Used by the `wl:` check verb (served out-of-process by candy/plugin-wl). Works on all wlroots compositors (sway, labwc). No daemon or special device access needed.

On KWin (KDE Plasma) the `wl:` verb reuses this candy's `wtype` (keyboard) and `wl-clipboard` (KWin implements `wlr-data-control`); window management on KWin is driven by `kdotool` (KWin scripting), which is shipped by the `kde-shell` candy (`/charly-selkies:kde-shell`), not this one. See the "What works where" table below.

**Note:** Screenshots are NOT included in this candy. Use `wl-screenshot-grim` (sway) or `wl-screenshot-pixelflux` (selkies) depending on your compositor.

## Candy Definition

```yaml
rpm:
  packages:
    - wtype
    - wlrctl
    - xdotool
    - xprop
    - xwininfo
    - wl-clipboard
    - wlr-randr
    - ydotool
```

No dependencies — compositor-agnostic. Works with sway, labwc, or any wlroots compositor.

## Key Properties

| Property | Value |
|----------|-------|
| Depends | None (compositor-agnostic) |
| Packages | `wtype`, `wlrctl`, `xdotool`, `xprop`, `xwininfo`, `wl-clipboard`, `wlr-randr`, `ydotool` |
| Service | None (all tools are one-shot CLI commands) |
| Ports | None |

## Tools

### Wayland Tools

| Tool | Protocol | Purpose |
|------|----------|---------|
| `wtype` | `zwp_virtual_keyboard_v1` | Keyboard input (type text, send keys, key combos with `-M`) |
| `wlrctl` | `wlr-virtual-pointer`, `wlr-foreign-toplevel-management` | Pointer control (move, click) + window management (list, focus, close, fullscreen, minimize) |
| `wl-copy` / `wl-paste` | `wlr-data-control` | Clipboard read/write |
| `wlr-randr` | `wlr-output-management` | Output resolution query and set |
| `ydotool` | `/dev/uinput` | Wayland-native mouse drag, scroll (press/release separation) |

### X11 Tools (via XWayland)

| Tool | Purpose |
|------|---------|
| `xdotool` | X11 window interaction (click, type, key, move, search, activate, scroll) |
| `xprop` | X11 window property inspection (WM_CLASS, _NET_WM_NAME, _NET_WM_PID) |
| `xwininfo` | X11 window geometry information |

All packages are in Fedora official repos.

## Included In

- `sway-desktop` metalayer (+ `wl-screenshot-grim` for screenshots)
- `selkies-desktop` metalayer (+ `wl-screenshot-pixelflux` for screenshots)

## What works where

| Tool | sway | labwc (selkies) | KWin (KDE Plasma) |
|------|------|-----------------|-------------------|
| wtype | YES | YES | YES (keyboard: type/key/key-combo) |
| wlrctl pointer | YES | YES | NO (no host-safe pointer backend; click/mouse/scroll/drag are unsupported on KWin) |
| wlrctl toplevel | YES | YES | NO — window management on KWin is via `kdotool` (from `kde-shell`) |
| wlr-randr | YES | YES | NO (resolution unsupported on KWin; kscreen-doctor hangs) |
| wl-clipboard | YES | YES | YES (KWin implements `wlr-data-control`) |
| xdotool | YES (XWayland) | YES (XWayland on-demand) | YES (XWayland on-demand) |
| ydotool | YES | YES (needs /dev/uinput) | n/a (KWin pointer is unsupported) |

On KWin the screenshot path is `pixelflux` (the same selkies capture bridge), the `wl: status` method reports `compositor: kwin` + `kdotool: available`, and the `wl:` verb routes window management (toplevel/windows/focus/close/fullscreen/minimize/geometry) through `kdotool`. KWin pointer (click/double-click/mouse/scroll/drag) and resolution are unsupported and return a clear "unsupported on KWin" error rather than hanging. The KWin-specific deploy-scope `wl` check checks live in the `kde-selkies` candy (`/charly-selkies:kde-selkies`).

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Cross-References

- `/charly-check:wl` — the `wl:` check verb that uses these tools (routes per compositor: wlroots via these tools, KWin via `kdotool`)
- `/charly-selkies:kde-shell` — KDE Plasma session candy that ships `kdotool` (KWin window-management automation, KWin-only)
- `/charly-selkies:kde-selkies` — KDE Plasma selkies flavor; hosts the KWin-specific deploy-scope `wl` check checks
- `/charly-selkies:wl-screenshot-grim` — Screenshot candy for sway (grim)
- `/charly-selkies:wl-screenshot-pixelflux` — Screenshot candy for selkies (pixelflux pipeline; also the KWin screenshot path)
- `/charly-selkies:sway-desktop` — Desktop metalayer that includes this candy
- `/charly-selkies:selkies-desktop-layer` — Desktop metalayer that includes this candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
