---
name: steam
description: |
  Steam gaming client with gamescope.
  Use when working with Steam, gaming, or gamescope in containers.
---

# steam -- Steam gaming client

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `sway` |
| Security | `shm_size: 1g` |
| Volume | `steam-data` -> `~/.local/share/Steam` |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `STEAM_RUNTIME_PREFER_HOST_LIBRARIES` | `0` |

## Packages

- `steam` (RPM, from RPM Fusion nonfree)
- `gamescope` (RPM, Fedora main repos)

XWayland is provided by the base `sway` candy.

## Usage

```yaml
# charly.yml — requires nvidia base (RPM Fusion nonfree via fedora-nonfree)
sway-browser-vnc-steam:
  base: nvidia
  candy:
    - sway-desktop-vnc
    - steam
```

## XWayland

Steam is an X11 application — it requires XWayland. The base sway config has `xwayland disable` for headless optimization. This candy installs a sway drop-in config at `~/.config/sway/config.d/xwayland.conf` that enables XWayland.

## Gamescope

Gamescope is a nested Wayland compositor for games. Use it in Steam launch options:

```
gamescope -W 1920 -H 1080 -r 60 -- %command%
```

Features: resolution spoofing, FSR/NIS upscaling, FPS limiting, HDR support.

## First Login

Steam Guard requires interactive login. Connect via VNC desktop, launch Steam, and log in manually. Auth tokens persist in the `steam-data` volume for subsequent container restarts.

## Related Candies

- `/charly-selkies:sway` — Wayland compositor (dependency)
- `/charly-selkies:sway-desktop-vnc` — Desktop composition with VNC
- `/charly-distros:cuda` — NVIDIA GPU support (via nvidia base)

## Used In Boxes

Not used in any current box definition. Standalone gaming candy requiring a Sway desktop box.

## When to Use This Skill

Use when the user asks about:

- Steam installation in containers
- Gaming on Sway/Wayland containers
- Gamescope configuration
- XWayland setup

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
