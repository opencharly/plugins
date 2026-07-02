---
name: selkies-desktop-layer
description: |
  Metalayer composing a full Selkies Wayland streaming desktop with Chrome, Waybar, desktop automation tools, and accessibility introspection.
  Use when working with the selkies-desktop metalayer composition, labwc desktop, or browser-accessible remote desktops.
---

# Candy: selkies-desktop

Metalayer composing a full Selkies Wayland streaming desktop with Chrome, Waybar, desktop automation tools, accessibility introspection, and XWayland support.

## Composition

The metalayer's composition is the `selkies-desktop-candy` child node (name-first node-form — the `candy:` list is never a bare top-level key). The full streaming-desktop set (the shared `selkies-core` spine pulls Chrome, the `wl-*` tooling, fonts, a11y, terminal tools transitively):

```yaml
selkies-desktop-candy:
  candy:
    - pipewire                # Audio (PulseAudio compat)
    - chrome                  # Google Chrome with CDP on :9222, Chrome DevTools MCP on :9224
    - labwc                   # Wayland compositor (nested in pixelflux)
    - waybar-labwc            # Top status bar (Catppuccin Mocha, system monitors)
    - desktop-fonts           # JetBrains Mono + Nerd Fonts
    - swaync                  # SwayNotificationCenter (notification daemon)
    - pavucontrol             # PulseAudio volume control GUI
    - wl-tools                # Desktop automation (wtype, wlrctl, xdotool, wl-clipboard, wlr-randr)
    - wl-screenshot-pixelflux # Screenshots via selkies capture bridge
    - wl-overlay              # Fullscreen overlays via gtk4-layer-shell (for recordings)
    - wl-record-pixelflux    # Desktop video recording via selkies capture bridge
    - a11y-tools              # AT-SPI2 accessibility introspection (python3-pyatspi)
    - xterm                   # X11 terminal for XWayland testing
    - tmux                    # Terminal multiplexer (required by the record: check verb)
    - asciinema               # Terminal session recording
    - fastfetch               # System information display
    - selkies                 # Streaming server (pixelflux + pcmflux + nginx)
```

## What You Get

A browser-accessible desktop at `http://localhost:3000` with:
- **labwc** Wayland compositor with server-side decorations
- **Waybar** top panel with system monitors, clock, audio, and notification bell
- **Chrome** auto-started maximized with CDP on port 9222 and `--force-renderer-accessibility`
- **foot** terminal (from labwc or fuzzel)
- **thunar** file manager (from labwc)
- **SwayNotificationCenter** notification daemon with Catppuccin Mocha theme
- **pavucontrol** PulseAudio volume control (click audio module in Waybar)
- **JetBrains Mono + Nerd Fonts** for sharp monospace text and icons
- **xterm** X11 terminal (triggers XWayland on-demand when launched)
- **pixelflux** Wayland capture → H.264/JPEG streaming at 60fps
- **pcmflux** audio capture → Opus encoding at 320kbps
- **PipeWire** audio server with PulseAudio compatibility
- **NGINX** web frontend on port 3000
- **Full `wl:` verb automation:** ~40 methods all working — screenshots (pixelflux), input (wtype, wlrctl), window management (wlrctl toplevel), clipboard (wl-copy/paste), resolution (wlr-randr), accessibility (AT-SPI2), XWayland tools (xdotool, xprop)
- **`cdp: coords` + `wl: click`:** CSS selector → desktop X/Y → Wayland pointer click (no VNC needed)
- **`cdp: axtree`:** Chrome accessibility tree via the `cdp:` verb
- **Desktop video recording** via the `record:` check verb (`record_mode: desktop`, capture bridge → H.264 → ffmpeg MP4, with optional audio)
- **Fullscreen overlays** via the `wl:` verb's `overlay-show` / `overlay-hide` methods (title cards, lower-thirds, countdowns, highlights, fades — rendered by compositor with true alpha transparency, no post-production needed)
- **Configurable keyboard layout** via `XKB_DEFAULT_LAYOUT` — German (de), French (fr), Nordic (no), etc. AltGr characters (@, €, \\, ~) work via direct scancode injection. See `/charly-selkies:labwc`

## What Works / What Doesn't

| Feature | Status | Notes |
|---------|--------|-------|
| Screenshots (pixelflux-screenshot) | WORKS | Via capture bridge at /tmp/charly-capture.sock |
| Screenshots (grim) | BROKEN | labwc nested in pixelflux can't deliver screencopy frames |
| wtype (keyboard) | WORKS | Wayland virtual keyboard |
| wlrctl pointer (mouse) | WORKS | Move, click, double-click |
| wlrctl toplevel (windows) | WORKS | List, focus, close, fullscreen, minimize. Matches by app_id only (v0.2.2) |
| wlr-randr (resolution) | WORKS | Query and set output resolution |
| wl-clipboard | WORKS | Get/set/clear clipboard |
| xdotool (X11 windows) | WORKS | Needs an X11 app running (xterm). XWayland starts on-demand |
| xprop (X11 properties) | WORKS | Search by `--class` first, then `--name` |
| AT-SPI2 (atspi) | WORKS | Uses `/usr/bin/python3` (system Python, not pixi) |
| ydotool (drag/scroll) | WORKS | Needs `/dev/uinput` access |
| CDP click --wl | WORKS | Selector → Wayland pointer (same coordinate space) |
| CDP axtree | WORKS | Chrome accessibility tree with filtering |
| wl-overlay (overlays) | WORKS | True alpha, ~15s screenshot latency in controller mode. Instant in recordings |

## Startup Order

| Priority | Service | Creates |
|----------|---------|---------|
| 2 | dbus | D-Bus session bus |
| 5 | pipewire | Audio server |
| 8 | selkies | pixelflux `wayland-1` + WebSocket :8081 (process-wide `ScreenCapture` singleton) |
| 12 | labwc | Desktop on `wayland-0` (nested in wayland-1) |
| 14 | swaync | Notification daemon (on wayland-0) |
| 15 | waybar | Top panel (on wayland-0) |
| 18 | nginx | Web UI on :3000 |

**Chrome ownership:** Chrome is launched + supervised by the `[program:chrome]` supervisord service in the shared `selkies-core` candy (`restart: always`), NOT by labwc's autostart — labwc's `autostart` no longer starts Chrome. The service is `autostart=true` and self-synchronizing (`chrome-wrapper` polls for the `wayland-0` client socket itself), so a single launcher serves both selkies flavors and there is no per-flavor `supervisorctl start` handoff to race. See `/charly-selkies:selkies-core` (Chrome supervision) and `/charly-selkies:chrome` (Chrome supervision) — the chrome candy supplies the cgroup memory caps.

**Capture singleton:** the selkies process owns a single process-wide `ScreenCapture` instance. Screenshot requests (`/charly-selkies:wl-screenshot-pixelflux`) and recording requests (`/charly-selkies:wl-record-pixelflux`) both attach to the same capture bridge at `/tmp/charly-capture.sock` — there is never a second capture process. This is the state enforced by commit `6be85eb` after the `WaylandBackend` leak investigation; the per-frame cleanup fix in commit `7977b91` is the paired memory-management step. See `/charly-selkies:selkies` (Pixelflux Memory Management) for the leak diagnosis, rollout recipe, and diagnostic commands.

## Used In Boxes

- `/charly-selkies:selkies-labwc`
- `/charly-selkies:selkies-labwc-nvidia`

## Known bootc caveat — labwc ↔ pixelflux start-order race

On container images, `ENTRYPOINT=supervisord` with priority-based startup sequences the desktop tier cleanly. On bootc images, supervisord runs under a systemd user service, and a start-order race surfaces that's invisible in container mode:

- `labwc-wrapper` blocks at startup waiting for `/tmp/wayland-1` (pixelflux's socket).
- `pixelflux` is started by `selkies` (another supervisord program) which — via its own ordering — comes up alongside labwc, not before it.
- With `startsecs=2`, supervisord marks labwc RUNNING before pixelflux is ready. labwc-wrapper times out, exits status 1, supervisord restarts it. Meanwhile selkies exits too (labwc isn't up). Both programs cycle every ~15 s.

Stable services (`traefik`, `selkies-fileserver`, `chrome-devtools-mcp`, `cdp-proxy`, `sshd`, `tailscaled`, `swaync`, `waybar`, `dbus`, `pipewire`) keep running; the HTTPS selkies web endpoint on port 3000 and the MCP endpoint on 9224 both stay responsive throughout.

Fix options for a follow-up pass (none implemented yet — this candy is shared between container and bootc modes):

1. Raise labwc's `startsecs` so supervisord waits for pixelflux before declaring labwc RUNNING.
2. Add an explicit `priority:` ordering via supervisord's eventlistener hooks — a `PROCESS_STATE_RUNNING` listener on selkies that `supervisorctl start`s labwc only after pixelflux publishes its socket.
3. Have labwc-wrapper spawn pixelflux directly as a child (the container-mode start order without relying on supervisord for ordering).

This race is a property of the candy's bootc mode (supervisord-under-systemd); no enabled box currently composes this candy in bootc mode, so the caveat is documented here from the candy's behavior rather than a live exemplar.

## Multi-Instance Proxy Deployment

Deploy multiple instances with different HTTP proxies. Each instance gets a port offset:

| Offset | Web (3000) | CDP (9222) | MCP (9224) | SSH (2222) |
|--------|-----------|-----------|-----------|-----------|
| 1 | 3001 | 9231 | 9241 | 2231 |
| 2 | 3002 | 9232 | 9242 | 2232 |
| N | 300N | 923N | 924N | 223N |

**Tunnel must be in charly.yml** for each instance. `charly config setup -i <ip>` does NOT inherit tunnel from the base entry. After config, manually add `tunnel: {provider: tailscale, private: all}` to the instance's charly.yml entry, then re-run `charly config setup -i <ip>` to regenerate the quadlet with Tailscale serve commands. See `/charly-core:deploy` for details.

**Chrome 147+ CDP:** The `/json/new` endpoint requires the PUT HTTP method (not GET). Use `curl -X PUT "http://localhost:<cdp-port>/json/new?<url>"` to create new tabs programmatically.

See `/charly-selkies:selkies-labwc` for full multi-instance deployment examples.

## Related Skills

- `/charly-selkies:selkies` — Streaming engine, Pixelflux Memory Management, ScreenCapture singleton, DRINODE auto-detection, keyboard layout support
- `/charly-selkies:labwc` — Nested Wayland compositor (its autostart no longer launches Chrome — selkies-core supervises it)
- `/charly-selkies:selkies-core` — owns the supervised `[program:chrome]` service shared by both selkies flavors
- `/charly-selkies:chrome` — Chrome browser with CDP proxy, HTTP proxy support, cgroup resource caps
- `/charly-infrastructure:supervisord` — supervisord process model (the selkies `[program:chrome]` uses `restart: always`)
- `/charly-selkies:wl-record-pixelflux` — Desktop video recording via the shared capture singleton
- `/charly-selkies:wl-screenshot-pixelflux` — Screenshots via the shared capture singleton
- `/charly-distros:arch-builder` — Builder image that compiles patched pixelflux from source on the cachyos base (`cuda-arch-builder` on the GPU build)
- `/charly-selkies:selkies-labwc` — CPU labwc box that bundles this metalayer (with `/charly-selkies:selkies-labwc-nvidia` for the GPU build)
- `/charly-check:wl` — Wayland automation (screenshots, input, windows)
- `/charly-check:cdp` — Chrome DevTools Protocol automation
- `/charly-check:record` — Desktop video recording via capture bridge
- `/charly-core:charly-update` — Per-instance update pattern used to roll out pixelflux/Chrome fixes
- `/charly-core:charly-config` — Multi-instance deployment, resource caps, tunnel, proxy env vars, NO_PROXY auto-enrichment
- `/charly-core:deploy` — Tunnel configuration (charly.yml-only, instance inheritance gap)

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, `run:`/`check:` step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
