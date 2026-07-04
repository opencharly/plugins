---
name: wl
description: |
  MUST be invoked before any work involving: Wayland desktop automation — the `wl:` check verb (screenshots, click/type/scroll/drag, window management, clipboard, resolution control, AT-SPI2 introspection, window geometry), its nested `wl: sway-*` / `wl: overlay-*` methods, or `wl:` declarative steps inside `check:`/`run:` blocks. Served out-of-process by `candy/plugin-wl`. Covers sway-desktop and selkies-desktop image automation on sway, labwc, AND KWin (KDE Plasma) — window management routes to wlrctl on wlroots and kdotool on KWin.
---

# WL - Wayland Desktop Automation

## Overview

The `wl:` check verb is the unified desktop automation verb for wlroots compositors (sway, labwc) **and KWin (KDE Plasma)**. It is **NOT a host `charly check` subcommand** — it is a declarative check verb served out-of-process by its plugin (`candy/plugin-wl`), parallel to the `cdp:`/`vnc:`/`dbus:` plugin verbs. Author a `wl:` step in a candy/box plan and run it against a live deployment with `charly check live <image> --filter wl`. It provides screenshots, input (click, type, key combos, scroll, drag), window management, clipboard, resolution control, accessibility introspection (AT-SPI2), and window geometry queries. Works on sway-desktop, selkies-desktop (labwc), and selkies-kde-desktop (KWin) images.

**Served out-of-process — no host CLI subcommand.** The host dispatches the `wl:` verb through the provider registry exactly like a built-in (`ResolveVerb("wl")` → the out-of-process gRPC provider → `Provider.Invoke` with the full `Op`), and the plugin drives the running container's compositor. Authoring is unchanged from a built-in verb: you write `wl: screenshot`, never `plugin: wl`.

**Per-compositor routing.** The plugin's `detectCompositor` picks the backend per method. On wlroots: `wlrctl` (pointer + `wlrctl toplevel` window management), `wlr-randr` (resolution). On **KWin**: window management (toplevel/windows/focus/close/fullscreen/minimize/geometry) via **`kdotool`** (KWin scripting) + screenshot via `pixelflux`; `status` reports `compositor: kwin`. KWin **keyboard** (type/key — `wtype` needs `zwp_virtual_keyboard_manager_v1`), **clipboard** (`wl-clipboard` needs `wlr-data-control`), **pointer** (click/double-click/mouse/scroll/drag) and **resolution** (`wlr-randr` needs `wlr-output-management`) have NO KWin backend — those wlroots protocols are unimplemented by KWin — so plugin-wl returns a clear "unsupported on KWin" error (not a hang). Proven live on `check-selkies-kde-pod`: `wl: status` → `compositor: kwin`. See the Compositor Compatibility table below.

### Authoring a `wl:` step

Each method is the declarative `wl:` step you author: the method name is the verb's YAML value, and method-specific fields (`x`, `y`, `text`, `key`, `combo`, `target`, `action`, `artifact`, `artifact_min_bytes`) are siblings of the verb line. Nested methods are hyphenated: `wl: overlay-show`, `wl: sway-tree`, `wl: sway-workspaces`. A query is a `check:` step; a side-effect action (click/type/exec/…) is a `run:` step. All `wl:` steps are **deploy-context only** (they need a running deployment), so author them with `context: [deploy]`. See `/charly-check:check` for the full method allowlist. Example:

```yaml
desktop-captured:
    check: a non-empty desktop screenshot is captured
    wl: screenshot
    context: [deploy]
    artifact: /tmp/desktop.png
    artifact_min_bytes: 10000
```

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Screenshot | `wl: screenshot` + `artifact:` | Capture desktop as PNG via grim |
| Click | `wl: click` + `x:` + `y:` | Click at absolute coordinates via wlrctl |
| Double-click | `wl: double-click` + `x:` + `y:` | Double-click with configurable delay |
| Type text | `wl: type` + `text:` | Send keyboard input via wtype |
| Send key | `wl: key` + `key:` | Press a named key via wtype |
| Key combo | `wl: key-combo` + `combo:` | Send key combination (ctrl+c, alt+tab) |
| Move mouse | `wl: mouse` + `x:` + `y:` | Move pointer to absolute coordinates |
| Scroll | `wl: scroll` + `x:` + `y:` + `action:` | Scroll at coordinates (up/down/left/right) |
| Drag | `wl: drag` + `x:` + `y:` (+ end coords) | Drag between coordinates (experimental) |
| List windows | `wl: windows` | List windows (wlrctl toplevel, xdotool fallback) |
| List toplevel | `wl: toplevel` | List Wayland toplevel windows via wlrctl |
| Focus window | `wl: focus` + `target:` | Focus window (wlrctl toplevel, xdotool fallback) |
| Close window | `wl: close` + `target:` | Close window via wlrctl toplevel |
| Fullscreen | `wl: fullscreen` + `target:` | Toggle fullscreen via wlrctl toplevel |
| Minimize | `wl: minimize` + `target:` | Toggle minimize via wlrctl toplevel |
| Launch app | `wl: exec` + `text:` | Launch application in container |
| Resolution | `wl: resolution` + `text:` | Set output resolution via wlr-randr |
| Clipboard | `wl: clipboard` + `action:` | Read/write Wayland clipboard (get/set/clear) |
| Window props | `wl: xprop` + `target:` | Query X11 window properties |
| Window rect | `wl: geometry` + `target:` | Get window position/size as JSON |
| A11y tree | `wl: atspi` + `action: tree` | Dump accessibility tree as JSON |
| A11y find | `wl: atspi` + `action: find` + `target:` | Find elements by name/role |
| A11y click | `wl: atspi` + `action: click` + `target:` | Click element by name/role |
| Status | `wl: status` | Check all tool availability |
| Overlay show | `wl: overlay-show` (+ overlay fields) | Show recording overlay (see `/charly-check:wl-overlay`) |
| Overlay hide | `wl: overlay-hide` | Remove overlays |

Run a candy's baked `wl:` steps against a live deployment with
`charly check live <image> --filter wl` (add `-i <instance>` for multi-instance).

## Compositor Compatibility

Backend availability per compositor (the plugin routes each method to the available one):

| Tool | Protocol | sway | labwc (selkies) | KWin (KDE Plasma) |
|------|----------|------|-----------------|-------------------|
| grim | wlr-screencopy | YES | NO (nested compositor) | NO |
| pixelflux-screenshot | pixelflux API | NO | YES | YES |
| wtype | zwp_virtual_keyboard_v1 | YES | YES | NO — fail-fast (KWin lacks the protocol) |
| wlrctl pointer | wlr-virtual-pointer | YES | YES | NO — pointer unsupported on KWin |
| wlrctl toplevel | wlr-foreign-toplevel-management | YES | YES | NO — window mgmt via `kdotool` |
| kdotool | KWin scripting (D-Bus) | NO | NO | YES (toplevel/focus/close/fullscreen/minimize/geometry) |
| wlr-randr | wlr-output-management | YES | YES | NO — resolution unsupported on KWin |
| wl-copy/paste | wlr-data-control | YES | YES | NO — fail-fast (KWin lacks wlr-data-control) |
| xdotool | X11 (XWayland) | YES | YES (on-demand) | YES (on-demand) |
| swaymsg | i3 IPC | YES | NO | NO |

**KWin (selkies-kde-desktop) notes.** On a headless rootless nested KWin pod the
wlroots-backed `wl:` tools do NOT work — KWin implements none of the wlroots
protocols they need, so `wtype` (keyboard), `wl-clipboard` (clipboard), and
`wlr-randr` (resolution) each HANG. `plugin-wl` is therefore **compositor-aware**
(`detectCompositor`): on KWin it routes **status** (`compositor: kwin`),
**screenshot** (`pixelflux`), and **window management** (toplevel/windows/focus/
close/fullscreen/minimize/geometry) through **`kdotool`** (KWin's D-Bus scripting),
and fail-fasts the wlroots paths with a clear "unsupported on KWin" error instead of
hanging. Pointer (click/double-click/mouse/scroll/drag) likewise has no host-safe
backend (`org_kde_kwin_fake_input` removed in KWin 6, RemoteDesktop portal
approval-gated, `/dev/uinput` leaks into the host) and returns the same clear error.
PROVEN live on `check-selkies-kde-pod`: the `wl-verb-dispatches` probe passes
(`wl: status` → `compositor: kwin`) alongside the desktop-ready + frame-not-black
stream coverage the labwc flavor also asserts. (The KDE session itself is a
`kwin_wayland --wayland-display wayland-1` nested compositor — see
`/charly-selkies:selkies-kde-desktop` "De-SDDM".)

**Coordinates.** The `wl:` verb takes **desktop-absolute** `x:`/`y:`. To click an
element located by CSS selector, read its desktop coordinates from a `cdp: coords`
step (it reports both viewport and desktop coords) and author the `wl: click` with
those `x:`/`y:` — see "CDP → WL Bridge" below.

## Architecture

```
host (charly check live --filter wl)
   -> resolve the venue (engine + container name)
   -> Op + venue handed to candy/plugin-wl over gRPC
candy/plugin-wl
   -> exec into the container: export WAYLAND_DISPLAY=… && <tool command>
   -> capture stdout (screenshot/query) or run silently (input)
```

The plugin `exec`s into the container. All tools use native Wayland protocols — no daemon, no `/dev/uinput`, no VNC server required.

## Requirements

- Container must include `wl-tools` layer (wtype, wlrctl, wl-clipboard, wlr-randr, xdotool, ydotool)
- For screenshots: `wl-screenshot-grim` (sway) or `wl-screenshot-pixelflux` (selkies)
- Container must have a running Wayland compositor (sway, labwc, etc.)
- For AT-SPI2: `a11y-tools` layer (python3-pyatspi, python3-gobject) + `dbus` layer
- For XWayland: an X11 app like `xterm` must be running to trigger XWayland start on labwc
- Included in `sway-desktop` and `selkies-desktop` metalayers

## Methods

Each method below is a `wl:` plan step authored with `context: [deploy]`; run a
candy's baked steps with `charly check live <image> --filter wl` (add
`-i <instance>` for a specific instance).

### Key Combo
```yaml
wl-key-combo:
    run: send a key combination
    wl: key-combo
    context: [deploy]
    combo: ctrl+shift+t        # also ctrl+c, alt+tab, super+l
```

Modifiers: `ctrl`/`control`, `alt`, `shift`, `super`/`win`/`logo`, `meta`. Uses `wtype -M`.

### Scroll
```yaml
wl-scroll:
    run: scroll down at the desktop center
    wl: scroll
    context: [deploy]
    x: 960
    y: 540
    action: down               # up/down/left/right
```

Uses xdotool click 4/5/6/7 (X11 scroll buttons) for XWayland windows. Falls back to wtype Page_Up/Page_Down.

### Drag (Experimental)
```yaml
wl-drag:
    run: drag from one point to another
    wl: drag
    context: [deploy]
    x: 100
    y: 100
    # end coordinates carried as the step's drag-target fields
```

Requires XWayland (uses `xdotool mousemove + mousedown/mouseup`).

### Window Management (wlrctl toplevel)
```yaml
wl-focus-chrome:
    run: focus a window by title
    wl: focus
    context: [deploy]
    target: Chrome             # also close / fullscreen / minimize via the matching method
wl-launch-terminal:
    run: launch a terminal in the container
    wl: exec
    context: [deploy]
    text: foot
```

`wl: toplevel` lists all windows; `wl: close` / `wl: fullscreen` / `wl: minimize` take the same `target:`.

### Resolution
```yaml
wl-resolution:
    run: set the output resolution
    wl: resolution
    context: [deploy]
    text: 1920x1080            # auto-detect output
```

### Clipboard
```yaml
wl-clipboard-set:
    run: write the Wayland clipboard
    wl: clipboard
    context: [deploy]
    action: set
    text: hello
```

`action: get` reads the clipboard; `action: clear` clears it.

### Window Geometry
```yaml
wl-geometry:
    check: the window geometry is reported
    wl: geometry
    context: [deploy]
    target: Chrome             # returns JSON: {"x":0,"y":0,"width":1920,"height":1080}
wl-xprop:
    check: the active window's X11 properties are reported
    wl: xprop
    context: [deploy]
```

### AT-SPI2 Accessibility
```yaml
wl-atspi-tree:
    check: the accessibility tree is dumped
    wl: atspi
    context: [deploy]
    action: tree               # dump full accessibility tree as JSON
wl-atspi-click:
    run: click an element by name AND role
    wl: atspi
    context: [deploy]
    action: click
    target: "Save:button"      # name / role / "name:role"
```

Requires `a11y-tools` layer. Chrome needs `--force-renderer-accessibility` flag.

### CDP → WL Bridge

Locate an element's viewport coords with the `cdp: coords` verb (CSS selector in
Chrome) — it reports both the viewport and the desktop center — then deliver the
click with a `wl: click` step at the reported desktop `x:`/`y:` (wlrctl pointer —
critical for selkies-desktop which has no VNC):

```yaml
submit-locate:
    check: the submit button is located
    cdp: coords
    context: [deploy]
    tab: "1"
    selector: "#submit-button"
submit-wl-click:
    run: deliver the click via the wl pointer at the reported desktop center
    wl: click
    context: [deploy]
    x: 640
    y: 360
```

## Sway-Specific Methods (`wl: sway-*`)

The sway IPC methods are the hyphenated `wl: sway-*` methods. They require a sway
compositor (swaymsg) and error on labwc.

```yaml
wl-sway-tree:
    check: the sway window tree is reported
    wl: sway-tree
    context: [deploy]
wl-sway-msg:
    run: run any swaymsg command
    wl: sway-msg
    context: [deploy]
    text: focus left
```

Other sway methods: `wl: sway-workspaces` / `sway-outputs` (JSON queries),
`sway-focus` / `sway-move` / `sway-resize` / `sway-kill` / `sway-floating` /
`sway-layout` / `sway-workspace` (window/workspace control via `target:`/`action:`),
and `sway-reload` (reload sway config).

## Differences from VNC

| Aspect | `wl:` verb | `vnc:` verb |
|--------|---------|----------|
| Compositors | All wlroots (+ sway-* methods) | Requires wayvnc |
| Transport | exec into container | TCP port 5900 |
| Window mgmt | wlrctl toplevel + sway IPC | No |
| Clipboard | wl-copy/paste | rfb cut-text |
| Remote access | No | Yes (TCP) |
| NVIDIA headless | Works | Works (pixman + DPMS fix) |

Source: `candy/plugin-wl` (the out-of-process Wayland-automation provider).

## Cross-References

- `/charly-check:check` — parent router; the `wl:` verb catalog entry, the method allowlist, and `charly check live <image> --filter wl`.
- `/charly-internals:plugin` — the out-of-process provider model that serves `wl` (`candy/plugin-wl`).
- `/charly-check:vnc` — VNC/RFB protocol alternative via the declarative `vnc:` verb (sibling verb; TCP-based, works remotely).
- `/charly-check:cdp` — Chrome DevTools Protocol via the declarative `cdp:` verb (sibling verb; DOM-level interaction, `axtree` for accessibility).
- `/charly-check:dbus` — D-Bus calls and desktop notifications via the declarative `dbus:` verb served out-of-process by `candy/plugin-dbus`.
- `/charly-selkies:wl-tools` — Compositor-agnostic tools (wtype, wlrctl, wl-clipboard, wlr-randr, xdotool, ydotool)
- `/charly-check:wl-overlay` — Fullscreen overlays for recordings (title cards, lower-thirds, countdowns, highlights, fades) via the `wl: overlay-*` methods
- `/charly-selkies:wl-overlay-layer` — Overlay layer (gtk4-layer-shell, python3-gobject)
- `/charly-selkies:wl-screenshot-grim` — Screenshot layer for sway (grim, wlr-screencopy)
- `/charly-selkies:wl-screenshot-pixelflux` — Screenshot layer for selkies (pixelflux rendering pipeline)
- `/charly-selkies:a11y-tools` — AT-SPI2 accessibility (python3-pyatspi, python3-gobject)
- `/charly-selkies:xterm` — X11 terminal for XWayland testing
- `/charly-selkies:sway-desktop` — Desktop metalayer (wl-tools + wl-screenshot-grim)
- `/charly-selkies:selkies-desktop-layer` — Desktop metalayer (wl-tools + wl-screenshot-pixelflux + a11y-tools + xterm)
