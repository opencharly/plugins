---
name: wl-overlay
description: |
  Fullscreen Wayland overlays for screen recordings via gtk4-layer-shell.
  MUST be invoked before any work involving: the `wl: overlay-*` methods, recording
  overlays, title cards, lower-thirds, countdowns, or fade transitions.
---

# WL Overlay -- Wayland Desktop Overlays for Recording

## Overview

The `wl: overlay-*` methods create and manage fullscreen Wayland overlays using the layer-shell protocol via gtk4-layer-shell. Overlays render directly in the compositor, appearing natively in screen recordings without post-production editing. Supports true alpha transparency — desktop content is visible through semi-transparent overlays. They are part of the `wl:` check verb — **NOT a host `charly check` subcommand** — served out-of-process by `candy/plugin-wl`. Author a `wl: overlay-show` / `wl: overlay-hide` step in a candy/box plan and run it against a live deployment with `charly check live <image> --filter wl`.

## Architecture

Three components work together:

1. **`wl-overlay` layer** — installs `gtk4-layer-shell`, `gtk4`, `python3-gobject` RPMs + `charly-overlay` Python daemon/client
2. **The `wl: overlay-*` methods** — dispatched out-of-process to `candy/plugin-wl`, which resolves the container and invokes `charly-overlay` inside it
3. **`charly-overlay` daemon** — GTK4 application managing multiple named overlay windows via Unix socket IPC

The daemon starts on-demand in a tmux session (`charly-overlay-daemon`) when the first `overlay-show` runs. It persists until `overlay-hide` (with `all: true`) or the tmux session is killed.

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Show overlay | `wl: overlay-show` (+ `type:` + `text:`) | Display a named overlay |
| Hide one | `wl: overlay-hide` + `name:` | Remove specific overlay |
| Hide all | `wl: overlay-hide` + `all: true` | Remove all overlays |
| List | `wl: overlay-list` | List active overlays (JSON) |
| Status | `wl: overlay-status` | Check daemon health |

## Overlay Types

Each example is a `wl: overlay-show` step authored with `context: [deploy]`. The former
CLI flags are the step's sibling fields (see "Overlay-show fields" below).

### Text (Title Card)

Full-screen semi-transparent overlay with centered text. Use for intro/outro title cards.

```yaml
overlay-title:
    run: show a title card
    wl: overlay-show
    context: [deploy]
    type: text
    text: Building a REST API
    bg: rgba(0,0,0,0.7)
    font_size: 64
    name: title
```

### Lower-Third

Bottom-anchored bar with name and optional subtitle. Use for speaker identification.

```yaml
overlay-speaker:
    run: show a lower-third speaker ID
    wl: overlay-show
    context: [deploy]
    type: lower-third
    text: Andreas Trawoeger
    subtitle: Developer
    name: speaker
```

### Watermark

Corner-anchored persistent text at low opacity. Use for draft/preview markers.

```yaml
overlay-watermark:
    run: show a draft watermark
    wl: overlay-show
    context: [deploy]
    type: watermark
    text: DRAFT
    position: bottom-right
    color: red
    opacity: 0.5
    name: wm
```

Default opacity is 0.3. Positions: `top-left`, `top-right`, `bottom-left`, `bottom-right`, `top`, `bottom`.

### Countdown

Full-screen animated countdown that auto-hides on completion. Use before recording starts.

```yaml
overlay-countdown:
    run: show a 5-second countdown
    wl: overlay-show
    context: [deploy]
    type: countdown
    seconds: 5
    name: cd
```

### Highlight

Transparent overlay with a colored rectangle at specified coordinates. Use to draw attention to a screen region.

```yaml
overlay-highlight:
    run: highlight a screen region
    wl: overlay-show
    context: [deploy]
    type: highlight
    region: "430,290,510,50"
    color: rgba(255,0,0,0.4)
    name: hl
```

Region format: `X,Y,Width,Height` in pixels.

### Fade

Full-screen solid color overlay. Use for transitions (fade to black, fade to white).

```yaml
overlay-fade:
    run: fade to black
    wl: overlay-show
    context: [deploy]
    type: fade
    color: black
    name: outro
```

## Duration Auto-Hide

Any overlay (except countdown, which has built-in auto-hide) can auto-remove after a duration via the `duration:` field:

```yaml
overlay-intro:
    run: show an intro card that auto-hides after 5s
    wl: overlay-show
    context: [deploy]
    type: text
    text: INTRO
    duration: 5s
    name: intro
```

Supported formats: `5s`, `1.5m`, `500ms`, or bare seconds (`5`).

## Recording Workflow

Overlays compose naturally with the declarative `record:` verb (`/charly-check:record`,
served out-of-process by `candy/plugin-record`): bracket the captured timeline with
`record: start` … `record: stop` plan steps, and drive the overlay actions with sibling
`wl: overlay-show` / `wl: overlay-hide` steps in the same plan. Run it with
`charly check live <image> --filter record --filter wl`.

```yaml
# candy/<name>/charly.yml — the recorded timeline as ordered record:/wl: steps
title-card:
    run: show the title card
    wl: overlay-show
    context: [deploy]
    type: text
    text: Building a REST API
    bg: rgba(0,0,0,0.9)
    font_size: 64
    name: title
record-begin:
    run: start the desktop recording
    record: start
    context: [deploy]
    record_mode: desktop
title-hide:
    run: fade out the title card
    wl: overlay-hide
    context: [deploy]
    name: title
lower-third:
    run: show the speaker lower-third
    wl: overlay-show
    context: [deploy]
    type: lower-third
    text: Andreas Trawoeger
    subtitle: Developer
    name: speaker
outro-fade:
    run: fade to black for the ending
    wl: overlay-show
    context: [deploy]
    type: fade
    color: black
    name: outro
record-end:
    run: stop and copy out the recording
    record: stop
    context: [deploy]
    artifact: /tmp/demo.mp4
overlay-clear:
    run: remove all overlays
    wl: overlay-hide
    context: [deploy]
    all: true
```

## Compositor Compatibility

All overlay types work on all wlroots-based compositors:

| Compositor | Environment | Status | Notes |
|-----------|-------------|--------|-------|
| sway | sway-browser-vnc | WORKS | Instant rendering, captured by wayvnc |
| labwc | selkies-desktop | WORKS | ~15s capture latency in controller mode (no browser). Instant in recordings |

### Key Technical Details

- **True RGBA transparency**: enabled by `window { background: none; }` CSS at daemon startup. Without this, GTK4 on Wayland creates opaque surfaces
- **Cairo-drawn backgrounds**: backgrounds are painted via `Gtk.DrawingArea` + Cairo, not CSS. GTK4 CSS `background-color` with `rgba()` does not composite correctly on layer-shell windows
- **Layer**: uses `Gtk4LayerShell.Layer.OVERLAY` (highest z-order, above waybar/swaync)
- **Keyboard**: `KeyboardMode.NONE` — overlays never capture input
- **Exclusive zone**: `-1` — overlays don't push other windows
- **Python interpreter**: uses `/usr/bin/python3` (system Python with PyGObject), not pixi's Python

### Selkies-Desktop Capture Latency

On selkies-desktop, `pixelflux-screenshot` captures from the H.264 WebSocket stream. In controller mode (no browser client connected), the frame rate is very low — screenshots may take 15-30 seconds to reflect overlay changes. **This does NOT affect recordings** — the `record:` verb captures at 30fps, so overlays appear immediately in recorded video.

## IPC Protocol

Socket: `/tmp/charly-overlay.sock` (Unix domain, JSON-line)

```json
{"action":"show","type":"text","text":"Hello","name":"intro","bg":"rgba(0,0,0,0.7)"}
{"action":"hide","name":"intro"}
{"action":"hide_all"}
{"action":"list"}
{"action":"status"}
```

## Overlay-show fields

The `wl: overlay-show` step carries these fields (the former CLI flags):

| Field | Default | Description |
|------|---------|-------------|
| `type` | (required) | `text`, `lower-third`, `watermark`, `countdown`, `highlight`, `fade` |
| `text` | `""` | Text content |
| `subtitle` | `""` | Subtitle (lower-third only) |
| `name` | auto-generated | Overlay identifier for hide/list |
| `position` | `center` | Positioning (watermark: corner anchoring) |
| `bg` | type-dependent | Background color (CSS rgba or named) |
| `color` | `white` | Text/highlight color |
| `font_size` | `48` | Font size in pixels |
| `opacity` | `1.0` (watermark: `0.3`) | Overall window opacity |
| `duration` | none | Auto-hide after duration (e.g. `5s`) |
| `seconds` | `3` | Countdown seconds |
| `region` | `100,100,400,300` | Highlight region `X,Y,W,H` |

## Requirements

- Container must include `wl-overlay` layer (gtk4-layer-shell + python3-gobject)
- Container must have a running Wayland compositor (sway, labwc)
- Container must have `tmux` layer (for daemon hosting)
- Included in `sway-desktop` and `selkies-desktop` metalayers

## Cross-References

- `/charly-check:wl` — Compositor-agnostic desktop automation via the `wl:` verb (screenshots, input, windows)
- `/charly-check:record` — Terminal and desktop recording via the `record:` verb (overlays compose with the recording workflow)
- `/charly-check:cdp` — Chrome DevTools Protocol via the `cdp:` verb (DOM-level interaction)
- `/charly-selkies:wl-overlay-layer` — Layer reference (RPM packages, dependencies)
- `/charly-selkies:sway-desktop` — Desktop metalayer (includes wl-overlay)
- `/charly-selkies:selkies-desktop-layer` — Desktop metalayer (includes wl-overlay)

Source: `candy/plugin-wl` (the out-of-process provider), `candy/wl-overlay/charly-overlay` (Python daemon/client).
