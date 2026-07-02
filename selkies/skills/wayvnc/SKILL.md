---
name: wayvnc
description: |
  WayVNC server on port tcp:5900 for remote access to Wayland desktops.
  Use when working with VNC access, remote desktop, or wayvnc configuration.
---

# wayvnc -- VNC server for Wayland compositors

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Ports | `tcp:5900` (non-HTTP protocol) |
| Service | `wayvnc` (supervisord, priority 20) |
| Install files | `task:`, `wayvnc-wrapper` |

## Packages

- `wayvnc` (RPM)

## Usage

```yaml
# charly.yml -- typically included via sway-desktop composition
my-desktop:
  candy:
    - wayvnc
```

```bash
charly check live my-image --filter vnc        # run the candy's vnc: screenshot / status steps
charly settings set vnc.password.my-image …    # store auth in the VNC credential store
# the candy's vnc: passwd step then configures VeNCrypt/TLS server-side
```

## NVIDIA Headless: Fixed via Pixman + DPMS Workaround

VNC screenshots work correctly on NVIDIA headless when used via `sway-desktop-vnc` (the standard VNC composition). Two fixes make this work:

1. **Pixman renderer** — `sway-desktop-vnc` sets `WLR_RENDERER=pixman` in its candy env, forcing software rendering. The `sway-wrapper` skips GPU auto-detection when `WLR_RENDERER` is pre-set.

2. **DPMS workaround** — wayvnc 0.9.1 gates screen capture on `zwlr_output_power_v1` mode events, but sway's headless backend never emits them. The `wayvnc-wrapper` performs a minimal VNC handshake to trigger wayvnc to bind the power manager, then `swaymsg "output HEADLESS-1 power on"` forces the missing event. Fixed in wayvnc git main (post-0.9.1) — remove workaround when Fedora ships the fix.

For boxes NOT using `sway-desktop-vnc` (custom sway + wayvnc setups), the `wl: screenshot` method (grim) remains a reliable fallback.

### Startup Timing

The `wayvnc-wrapper` uses a two-phase wait:
1. Wait for Wayland display socket (`wayland-0`)
2. Wait for sway IPC socket (`sway-ipc.*.sock`) + 2s delay

This ensures sway has set the output resolution (default 1920x1080) before wayvnc connects.

## Used In Boxes

Part of `/charly-selkies:sway-desktop` composition.

## Related Candies

- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-selkies:sway` -- Wayland compositor (provides display)
- `/charly-selkies:sway-desktop` -- composition that includes wayvnc
- `/charly-selkies:pipewire` -- sibling in desktop stack

## Related Commands

- `/charly-check:vnc` — VNC screenshot, click, type, key, mouse commands

## When to Use This Skill

Use when the user asks about:

- VNC server setup or configuration
- Remote desktop access to containers
- Port 5900 (tcp protocol)
- VNC password or TLS authentication
- wayvnc wrapper or configuration

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
