---
name: labwc
description: |
  Lightweight Wayland compositor (wlroots-based) for nested desktop inside pixelflux.
  MUST be invoked when working with: the labwc candy, Wayland compositor config in selkies boxes, or labwc-wrapper.
---

# labwc -- Nested Wayland compositor for Selkies desktop

Lightweight Wayland compositor (wlroots-based) for use as a nested desktop inside pixelflux's Wayland capture compositor.

## Architecture

labwc runs as a **nested compositor** inside pixelflux's `wayland-1` display. It creates its own `wayland-0` socket for desktop applications (Chrome, Waybar, foot, thunar). This is the same approach used by the LinuxServer.io Selkies base image.

- labwc connects to `wayland-1` (pixelflux) via `WAYLAND_DISPLAY=wayland-1` in the labwc-wrapper
- labwc creates `wayland-0` for its clients
- The global env `WAYLAND_DISPLAY=wayland-0` ensures apps connect to labwc, not pixelflux

## Dependencies

- `dbus`

## Packages

- `labwc` — Wayland compositor
- `foot` — Terminal emulator
- `xorg-x11-server-Xwayland` — X11 compatibility
- `thunar` — File manager

## Environment

| Variable | Value | Purpose |
|----------|-------|---------|
| `WAYLAND_DISPLAY` | `wayland-0` | labwc's client socket (global default for apps) |
| `XDG_RUNTIME_DIR` | `/tmp` | Runtime directory |

## Keyboard Configuration

labwc-wrapper exports all XKB environment variables with defaults, making keyboard layout configurable at deploy time:

| Variable | Default | Purpose |
|----------|---------|---------|
| `XKB_DEFAULT_LAYOUT` | `us` | Keyboard layout (us, de, fr, gb, es, no, etc.) |
| `XKB_DEFAULT_VARIANT` | (empty) | Layout variant (dvorak, nodeadkeys, etc.) |
| `XKB_DEFAULT_MODEL` | `pc105` | Keyboard model (pc105, pc104, chromebook) |
| `XKB_DEFAULT_OPTIONS` | (empty) | XKB options (compose:ralt, caps:escape) |
| `XKB_DEFAULT_RULES` | `evdev` | XKB rules (always evdev, not configurable) |

All except RULES are declared as `env_accept` — override via `charly config -e`:

```bash
# German QWERTZ layout
charly config selkies-desktop -e XKB_DEFAULT_LAYOUT=de

# French AZERTY with no dead keys
charly config selkies-desktop -e XKB_DEFAULT_LAYOUT=fr -e XKB_DEFAULT_VARIANT=nodeadkeys
```

The compositor and selkies input handler both read `XKB_DEFAULT_LAYOUT` from the environment, ensuring the scancode map matches the compositor's layout. See `/charly-selkies:selkies` for the keyboard input pipeline details.

## Service (supervisord)

| Service | Priority | Purpose |
|---------|----------|---------|
| `labwc` | 12 | Desktop compositor (after selkies at priority 8) |

## Key Files

- `labwc-wrapper` — Waits for pixelflux's `wayland-1` socket, exports XKB_DEFAULT_* from env with defaults, then starts labwc
- `rc.xml` — labwc configuration: server-side decorations, maximize-all window rule, keyboard shortcuts (Alt+F4 close, Super+E terminal)
- `autostart` — Does NOT launch Chrome. Chrome is launched + supervised by the
  `[program:chrome]` service in the **selkies-core** candy (shared by both selkies
  flavors). CDP: internal 9223, external 9222 via cdp-proxy.

## Chrome ownership (selkies-core, not labwc)

Chrome is owned by a supervised `[program:chrome]` service declared in the
**selkies-core** candy (`candy/selkies-core/charly.yml` `service:` block) — NOT by the
labwc candy and NOT by labwc's autostart. Both selkies flavors (labwc via
`selkies-desktop`, KDE Plasma via `selkies-kde-desktop`) compose selkies-core and get the
same supervised browser. The per-flavor compositor autostart (labwc's `autostart`,
KDE's `kde-selkies-session`) does not start Chrome.

The supervised service uses:

- `restart: always` → `autorestart=true`. The selkies flavors nest the compositor inside
  pixelflux's `wayland-1`; a Chrome started during the nested compositor's startup-race
  self-exits once (clean exit 0, the window-less browser's sole window going away on the
  early color-manager re-init). `autorestart=true` relaunches it post-settle, where it
  stays up indefinitely.
- `autostart=true` (default) and **self-synchronizing**: `chrome-wrapper` itself polls for
  the `wayland-0` client socket (created by the nested compositor), so no per-flavor
  handoff is needed.
- `start_secs: 5` + `start_retries: 3`: the single startup-race self-exit runs longer than
  `start_secs`, so it resets the retry budget and never trips `FATAL`.
- `priority: 30`, env `WAYLAND_DISPLAY=wayland-0`.

There is no Chrome eventlistener and no `PROCESS_STATE_FATAL` circuit breaker — relaunch is
handled entirely by `restart: always` on the supervised service. The chrome candy's cgroup
resource caps (`memory_max`/`memory_high`/`memory_swap_max`/`shm_size`) still apply. See
`/charly-selkies:selkies-desktop-layer` and `/charly-infrastructure:supervisord` for the
supervised-service pattern, and `/charly-selkies:chrome` for the resource caps.

**sway-browser-vnc is unaffected:** it launches Chrome via the chrome-sway candy (not
selkies-core), is not pixelflux-nested, and does not hit the startup-race.

## Window Rules

All windows open maximized (ideal for streaming desktop):
```xml
<windowRule identifier="*" serverDecoration="yes">
  <action name="Maximize" />
</windowRule>
```

## Used In Boxes

- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Skills

- `/charly-selkies:selkies` — pixelflux streaming engine (provides `wayland-1` that labwc connects to)
- `/charly-selkies:selkies-desktop-layer` — desktop metalayer that composes labwc + chrome + waybar + selkies
- `/charly-selkies:waybar-labwc` — status bar configured for labwc
- `/charly-selkies:chrome` — Chrome browser (supervised by the selkies-core `[program:chrome]` service)
- `/charly-check:wl` — Wayland automation commands (screenshots, input, window management). Supports KWin (KDE Plasma) in addition to wlroots (sway/labwc); on labwc it uses the wlroots backends (wlrctl pointer/toplevel, wlr-randr, wtype, wl-clipboard, pixelflux-screenshot)

## When to Use This Skill

**MUST be invoked** when the task involves the labwc candy, Wayland compositor configuration in selkies boxes, the labwc-wrapper script, window rules, or the nested compositor architecture (pixelflux → labwc → apps).

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
