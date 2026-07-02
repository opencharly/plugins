---
name: sway
description: |
  Sway Wayland compositor running headless inside containers with Mesa GPU drivers.
  Use when working with Sway, Wayland desktop, or headless compositor setup.
---

# sway -- Headless Wayland compositor

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `dbus` |
| Service | `sway` (supervisord, priority 10) |
| Install files | `task:`, `config`, `sway-wrapper` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `WLR_BACKENDS` | `headless` (supervisord env) |
| `WLR_HEADLESS_OUTPUTS` | `1` |
| `WLR_LIBINPUT_NO_DEVICES` | `1` |
| `XDG_RUNTIME_DIR` | `/tmp` |
| `WAYLAND_DISPLAY` | `wayland-0` |
| `EGL_LOG_LEVEL` | `fatal` |
| `XKB_DEFAULT_LAYOUT` | `us` |

### Keyboard Configuration

Keyboard layout defaults to US. Override with `env_accept` vars:

| Variable | Default | Purpose |
|----------|---------|---------|
| `XKB_DEFAULT_LAYOUT` | `us` | Keyboard layout (us, de, fr, gb, etc.) |
| `XKB_DEFAULT_VARIANT` | (empty) | Layout variant (dvorak, nodeadkeys, etc.) |

```bash
charly config sway-desktop -e XKB_DEFAULT_LAYOUT=de
```

Sway reads `XKB_DEFAULT_LAYOUT` natively from the environment — no wrapper change needed. See `/charly-selkies:labwc` for full XKB var list (MODEL, OPTIONS).

The supervisord `[program:sway]` environment sets `WLR_BACKENDS=headless` — headless output only. The `libinput` backend is **not** included by default because it requires a libseat session which fails in rootless containers.

## Packages

- `sway`, `fuzzel` (RPM)
- `mesa-dri-drivers`, `mesa-vulkan-drivers` (RPM)
- `libglvnd-egl`, `libglvnd-gles`, `egl-wayland` (RPM)
- `wlr-randr` (RPM)

## Usage

```yaml
# charly.yml -- typically not used directly; pulled in via chrome-sway
my-desktop:
  candy:
    - sway
```

## XWayland

XWayland is **enabled by default** (`xwayland enable` in the base config). The `xorg-x11-server-Xwayland` package is included in the sway candy. XWayland starts lazily — the Xwayland process only launches when the first X11 client connects (e.g., Steam, Heroic, Qt apps with xcb platform).

X11 tools for interacting with XWayland windows (`xdotool`, `xprop`, `xwininfo`, `import`) are provided by the `/charly-selkies:wl-tools` candy.

## Stale IPC Socket Cleanup

Supervisord restarts leave old `/tmp/sway-ipc.1000.<old-pid>.sock` files. If multiple sockets exist, naive discovery (`ls /tmp/sway-ipc.*.sock | head -1`) picks alphabetically -- which selects the smallest PID (oldest = stale socket), causing the `wl:` verb's sway-* methods to fail silently.

**Fix**: `sway-wrapper` cleans old sockets before starting Sway. Both `sway-wrapper` and the `wl:` sway-* methods (now in candy/plugin-wl) use `ls -t | head -1` (newest modification time first) when discovering the active socket.

**Symptoms of stale socket**: the `wl:` verb's sway-* methods fail, resolution stays at 1280x720 (wlr-randr resize fails), Chrome renders at wrong size.

## NVIDIA Headless: Renderer

By default, `sway-wrapper` auto-detects GPU hardware and uses `gles2` on NVIDIA. However, if `WLR_RENDERER` is pre-set (e.g., by a composing layer), the wrapper skips GPU auto-detection entirely and uses the specified renderer.

- **VNC boxes** (`sway-desktop-vnc`) override to `pixman` (software rendering) — ensures reliable VNC screenshot capture on NVIDIA headless
- **Non-VNC boxes** (Sunshine, standalone sway) use `gles2` via auto-detection — Chrome gets full GPU acceleration
- `grim` (the `wl: screenshot` method) works with both renderers

## Used In Boxes

Transitive dependency via `chrome-sway` and `sway-desktop` in all desktop boxes.

## Related Candies

- `/charly-infrastructure:dbus-layer` -- D-Bus session bus dependency
- `/charly-selkies:chrome-sway` -- Chrome on Sway (depends on sway)
- `/charly-selkies:sway-desktop` -- full desktop composition (VNC)
- `/charly-selkies:wayvnc` -- VNC access to Sway display
- `/charly-selkies:waybar` -- status bar (depends on sway)

## Related Commands

- `/charly-check:wl` — Wayland desktop automation (screenshot, input, windows, clipboard, AT-SPI2)

## When to Use This Skill

Use when the user asks about:

- Sway compositor configuration
- Headless Wayland setup
- `WLR_BACKENDS` or Wayland environment variables
- Mesa GPU driver configuration
- Desktop compositor in containers

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
