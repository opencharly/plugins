---
name: sway-desktop-vnc
description: |
  Sway desktop with VNC remote access via wayvnc on port 5900.
  Composes sway-desktop base with wayvnc.
---

# sway-desktop-vnc -- Desktop with VNC remote access

## Candy Properties

| Property | Value |
|----------|-------|
| Candies (composition) | `sway-desktop`, `wayvnc` |
| Install files | none (pure composition) |

## NVIDIA Support

Forces `WLR_RENDERER=pixman` (software rendering) via candy env. This ensures VNC screenshots work reliably on all hardware, including NVIDIA headless. The `wayvnc-wrapper` includes a DPMS workaround for wayvnc 0.9.1's headless power event bug (to be removed when Fedora ships a fixed version).

## Used In Boxes

- `/charly-selkies:sway-browser-vnc`

## Related Candies

- `/charly-selkies:sway-desktop` -- base desktop (composed)
- `/charly-selkies:wayvnc` -- VNC server on tcp:5900 (added)

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
