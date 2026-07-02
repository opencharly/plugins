---
name: pavucontrol
description: |
  PulseAudio volume control GUI for desktop containers with PipeWire audio.
  Use when working with audio configuration or volume control.
---

# pavucontrol -- PulseAudio Volume Control

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `pipewire` |
| Service | none (GUI app, launched on demand) |
| Install files | `charly.yml` only |

## Packages

- `pavucontrol` (RPM)

## Usage

Launched on demand from waybar's pulseaudio module (click the volume indicator) or from a terminal:

```bash
pavucontrol &
```

## Waybar Integration

The waybar `pulseaudio` module has `"on-click": "pavucontrol"` — clicking the volume indicator in the status bar opens pavucontrol.

## Used In

- `/charly-selkies:sway-desktop` -- via metalayer composition
- `/charly-selkies:selkies-desktop-layer` -- via metalayer composition

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Candies

- `/charly-selkies:pipewire` -- audio server (provides PulseAudio compatibility)
- `/charly-selkies:waybar` -- volume indicator with pavucontrol on-click
- `/charly-selkies:waybar-labwc` -- same volume indicator

## When to Use This Skill

Use when the user asks about:

- Audio volume control in desktop containers
- PulseAudio/PipeWire GUI configuration
- pavucontrol setup

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
