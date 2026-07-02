---
name: selkies
description: |
  Browser-accessible desktop streaming via WebSocket using pixelflux and pcmflux.
  Use when working with Selkies streaming engine, pixelflux, pcmflux, or browser-based remote desktop.
---

# Candy: selkies

Browser-accessible desktop streaming via WebSocket using pixelflux (Wayland capture) and pcmflux (audio), served over HTTPS via Traefik with a self-signed certificate.

## Architecture

Selkies acts as a **nested Wayland compositor** via pixelflux. It creates `wayland-1`, and labwc (the desktop compositor) renders into it. Pixelflux captures the output and streams it to the browser via WebSocket. Traefik terminates TLS and proxies both the static web UI and WebSocket traffic.

```
Browser → Traefik (:3000 HTTPS, self-signed cert)
               ├── / → selkies-fileserver (:3001, static web UI)
               └── /websockets → Selkies Python (:8081)
                                    ├── pixelflux: Wayland capture → H.264
                                    ├── pcmflux: PulseAudio → Opus audio
                                    ├── xkbcommon: keyboard/mouse → Wayland inject
                                    └── capture bridge → /tmp/charly-capture.sock
                                          ↓
                               labwc (wayland-0, nested in pixelflux wayland-1)
```

HTTPS is required because the Selkies web UI uses the WebCodecs API (`VideoDecoder`), which requires a secure context.

### Capture Bridge

The `selkies-capture-server` runs **inside the selkies process** as a background thread, started by `selkies-wrapper` before selkies main(). It dynamically switches between **controller** mode (starts the capture pipeline when no browser is connected) and **viewer** mode (passively receives broadcast frames alongside a browser).

This is the ONLY working capture path for screenshots and recording on selkies-desktop. The pixelflux Rust backend only supports one active `ScreenCapture` at a time, and grim doesn't work because labwc can't deliver wlr-screencopy frames when nested.

**Mode switching:**
- Starts as controller → sends SETTINGS + START_VIDEO → pipeline runs
- Browser connects → server sends KILL → bridge reconnects as viewer → receives broadcast frames
- Browser disconnects → PIPELINE_RESETTING or empty buffer → reconnects as controller
- Screenshot handler can request reconnect if no valid H.264 frames (self-healing)

**H.264 frame filtering:** The selkies server broadcasts both H.264 video (`0x04` prefix + 10-byte header) and Opus audio (`0x01 0x00` prefix) as binary WebSocket messages. The bridge filters by prefix, only buffering H.264 video frames and stripping the 10-byte selkies header before storing. Audio for recording is captured separately via PulseAudio.

**Protocol on `/tmp/charly-capture.sock`:**
- `SCREENSHOT\n` → 4-byte length + PNG data (or 0 + reason string on failure)
- `STREAM\n` → continuous (4-byte length + raw H.264 frame data)
- `STATUS\n` → 4-byte length + JSON status (`connected`, `mode`, `frames`, `seq`, `active_streams`, `last_error`)

## Pixelflux Memory Management

Pixelflux's Wayland backend is expensive to construct: each `ScreenCapture` creates an EGL context, dmabuf allocators, GPU texture pools, and ffmpeg codec state. Two commits in April 2026 locked down its memory behavior after a month of debugging a slow virtual-address-space leak that manifested on long-running selkies-desktop instances (9 GB of mapped virtual memory after a 20-minute streaming session).

### ScreenCapture singleton (commit `6be85eb`)

The `ScreenCapture` instance is **process-wide**. `selkies_core.reconfigure_displays()` — which runs when the browser client changes resolution or when the compositor output geometry changes — now **mutates** the existing capture (updating dimensions, rebuilding the pipeline in place) instead of spawning a new one. Before the fix, every reconfiguration spawned a new `WaylandBackend` without freeing the old one, leaking the whole EGL+dmabuf construction set. The symptom was reproducible on any instance with a browser client that resized the window; the cumulative leak scaled with the number of reconfigure events.

Diagnostic recipe (use this when investigating a suspected selkies memory leak):

```bash
# Virtual address-space size (VmSize) of the selkies process
charly shell selkies-desktop -c "grep VmSize /proc/\$(pgrep -f selkies_core)/status"

# Count WaylandBackend instances in heap state (should always be 1)
charly shell selkies-desktop -c "ls -la /proc/\$(pgrep -f selkies_core)/map_files/ | wc -l"

# Watch the above repeatedly while a browser reconnects / resizes
watch -n5 "charly shell selkies-desktop -c 'grep VmSize /proc/\$(pgrep -f selkies_core)/status'"
```

If `VmSize` grows monotonically across reconfigure events, the singleton is broken — investigate `reconfigure_displays()` for regressions.

### Per-frame `cleanup_texture_cache()` (commit `7977b91`)

`cleanup_texture_cache()` runs **per frame** (not per capture session) in pixelflux's renderer main loop. It releases dmabuf imports whose Wayland buffer reference has already been dropped — these accumulate across frames because the EGL image-dmabuf import cache holds a GPU-side reference that the CPU-side `wl_buffer_release` does not clear. Without per-frame cleanup, a 60 fps stream leaks ~60 dmabuf handles per second even though `VmSize` stays flat (the leak is GPU-side, visible as increasing `nvidia-smi` memory usage on NVIDIA, `radeontop` on AMD).

This fix was rolled out via `charly update -i INSTANCE` across all live selkies-desktop instances — see `/charly-core:charly-update` for the per-instance update pattern. The rollback recipe there also applies if a pixelflux patch regresses.

### Rebuild cadence

Pixelflux is compiled **from source** in the selkies build stage (`candy/selkies/build.sh`), not installed from PyPI, because these fixes live on a fork not yet merged upstream. The build stage clones from a pinned commit, applies four inline source patches, and runs `pip install .` against the box's pixi builder (`arch-builder` on the cachyos base, `cuda-arch-builder` on the GPU build). See `/charly-distros:arch-builder` and `/charly-coder:build-toolchain` (5 package categories — smithay backend headers, codec devel, bindgen runtime, rust, generic C/C++) for the builder-stage dependency story.

### Related fixes

- `/charly-selkies:wl-screenshot-pixelflux` — Reuses the singleton capture path for screenshots
- `/charly-selkies:wl-record-pixelflux` — Reuses the singleton capture path for recording
- `/charly-selkies:selkies-labwc` — Build Pipeline Note explaining the patched pixelflux compilation

## Installation

Selkies is installed from `selkies-project/selkies` commit `af1a1c2` (not the PyPI `selkies` package, which is the old GStreamer-based upstream). The LSIO fork declares `pixelflux` and `pcmflux` as direct dependencies. `av` and `cryptography` deps are stripped before install (not needed for websocket mode).

Build-time dependencies (gcc, nodejs, npm, python3-devel, libxkbcommon-devel) are handled in the pixi builder stage via `build.sh` — they never appear in the final image. The web UI dashboard is built in the same builder stage.

## Dependencies

- `supervisord`, `python`, `pipewire`

## Ports

| Port | Protocol | Backend Scheme | Service |
|------|----------|---------------|---------|
| 3000 | HTTPS | `https+insecure` | Traefik (web UI + WebSocket proxy, self-signed cert) |
| 8081 | WebSocket | (internal only) | Selkies streaming backend |

Port 3000 uses `https+insecure` backend scheme because Traefik terminates TLS with a self-signed certificate. When tunneled via Tailscale, this generates `tailscale serve --bg --https=3000 https+insecure://127.0.0.1:3000` — Tailscale terminates TLS on the tailnet side and proxies to the self-signed HTTPS backend. Plain `http://` proxying would get 404 from Traefik.

## Environment

| Variable | Value | Purpose |
|----------|-------|---------|
| `PIXELFLUX_WAYLAND` | `true` | Enable Wayland capture mode |
| `DRINODE` | Auto-detected | GPU render node — injected at runtime by `charly config` from first `/dev/dri/renderD*` device. See `/charly-core:charly-config` |
| `DRI_NODE` | Auto-detected | Same as DRINODE — required by selkies VAAPI encoder. Override with `-e DRINODE=/dev/dri/renderDN` |
| `PULSE_SERVER` | `unix:/tmp/pulse/native` | PipeWire PulseAudio socket |
| `LANG` | `C.UTF-8` | UTF-8 locale — enables wtype to handle non-ASCII characters (ö, é, å, ñ, etc.) |

## Keyboard Layout Support

Selkies supports any keyboard layout via XKB environment variables. The compositor (labwc/sway) and the selkies input handler both read `XKB_DEFAULT_LAYOUT` from the environment. Set the layout at deploy time:

```bash
charly config selkies-desktop -e XKB_DEFAULT_LAYOUT=de    # German QWERTZ
charly config selkies-desktop -e XKB_DEFAULT_LAYOUT=fr    # French AZERTY
```

See `/charly-selkies:labwc` for the full list of XKB variables (LAYOUT, VARIANT, MODEL, OPTIONS).

### Input Pipeline

The browser captures keyboard events and sends keysyms via WebSocket. The selkies Python server translates keysyms to scancodes using an xkbcommon keymap that matches the compositor's layout, then injects scancodes via pixelflux.

`build.sh` patches `input_handler.py` at build time with five fixes for generic layout support:

| Patch | What it does |
|-------|-------------|
| Env-based keymap | Reads `XKB_DEFAULT_*` from env instead of hardcoding US layout |
| Latin-1 bypass removal | Layout chars (ö, é, å, ñ) go through scancode map, not wtype |
| Level 2 scanning | AltGr characters (@, €, \\, ~) added to scancode map |
| AltGr direct injection | Injects AltGr scancode + key scancode via pixelflux (same device) |
| Euro bypass removal | € uses scancode map like all other characters |

### AltGr Characters

The browser sends AltGr as a **momentary press/release** (not held). By the time the character keysym arrives, AltGr is no longer in the server's active modifier set. The server handles this by injecting a complete AltGr+key sequence directly through pixelflux when it detects a level-2 keysym. This avoids the wtype fallback which races with pixelflux's input device (different Wayland clients, timing-sensitive).

### LANG=C.UTF-8

The `C.UTF-8` locale (built-in to glibc, no package needed) ensures `wtype` can decode non-ASCII characters in its argv. Without it, wtype fails with "Failed to deencode input argv" for characters like ö, ä, ü. This is the fallback path for characters not in the scancode map.

## Services (supervisord)

| Service | Priority | Purpose |
|---------|----------|---------|
| `selkies` | 8 | Streaming server (creates pixelflux wayland-1) |
| `traefik` | 18 | HTTPS reverse proxy on port 3000 (self-signed cert) |
| `selkies-fileserver` | 19 | Python static file server for web UI (port 3001, internal) |

## Key Files

- `selkies-wrapper` — GPU detection, PulseAudio null sink setup, NVRTC library path, starts selkies via capture server
- `selkies-capture-server` — WebSocket→Unix socket bridge with controller/viewer mode switching, H.264 frame filtering, self-healing screenshots, STATUS command
- `selkies-fileserver` — Python SPA file server with index.html fallback (serves `/usr/local/share/selkies/web/`)
- `traefik.yml` — Traefik static config (HTTPS entrypoint on :3000, self-signed cert)
- `traefik-dynamic.yml` — Path-based routing (`/websockets` → :8081, `/` → :3001) with TLS default certificate
- `build.sh` — Pixi builder stage script: pip installs selkies (C extensions), patches `input_handler.py` for generic keyboard layout support (env-based keymap, AltGr injection, bypass removal), builds web UI dashboard (npm), stages artifacts for copy to final image
- `task:` — Downloads Traefik binary, generates self-signed cert, installs configs (no build deps, no dnf remove)
- `pixi.toml` — Python 3.13 + pip + setuptools + libxkbcommon (C headers for builder stage)

## GPU Encoding Status

| GPU | Rendering | Encoding | Status |
|-----|-----------|----------|--------|
| NVIDIA (CDI) | GL via auto-detected renderD | NVENC attempted but fails (pixelflux compat issue with driver 590.48) | Working GL, CPU encoding fallback |
| AMD | Mesa VA-API via auto-detected renderD | VAAPI hardware H264 encoding | Working — requires correct DRINODE (auto-detected by `charly config`) |
| Intel | Mesa VA-API via auto-detected renderD | VAAPI available | Untested |
| CPU | pixman fallback | x264enc / x264enc-striped / jpeg | Working but causes flickering at high resolutions |

**DRINODE auto-detection:** `charly config` detects the first `/dev/dri/renderD*` device on the host and injects `DRINODE` and `DRI_NODE` env vars at runtime via `appendAutoDetectedEnv()`. Previously these were hardcoded to `renderD129` in `charly.yml`, causing VAAPI encoder failure on hosts with `renderD128` — the encoder fell back to CPU software encoding, which caused labwc swapchain buffer exhaustion (`No free output buffer slot`) and visible stream flickering. See `/charly-internals:go` for implementation details.

**NVENC note:** pixelflux detects the GPU, CUDA initializes, but NVENC encoder init fails. All NVIDIA libraries load correctly (libnvidia-encode, libcuda, libnvrtc). Likely a pixelflux compatibility issue with driver 590.48. CPU x264enc at 60fps with striped mode (16 parallel stripes) provides acceptable performance.

**Important:** Setting `SELKIES_ENCODER=x264enc-striped` locks to CPU mode. Leave encoder unset for GPU auto-detection.

## Volumes

- `selkies-config` → `~/.config/selkies`

## Used In Boxes

- `/charly-selkies:selkies-labwc`
- `/charly-selkies:selkies-labwc-nvidia`

## Related Candies

- `/charly-selkies:labwc` — Nested compositor that selkies hosts inside `wayland-1` (autostart Chrome-duplication race + keyboard layout)
- `/charly-selkies:chrome` — Chrome browser (supervised by the `[program:chrome]` service in `selkies-core`) + cgroup resource caps
- `/charly-infrastructure:supervisord` — Service ordering, event listeners, crash-loop escalation
- `/charly-selkies:wl-screenshot-pixelflux` — Screenshot path via the shared ScreenCapture singleton
- `/charly-selkies:wl-record-pixelflux` — Recording path via the shared ScreenCapture singleton
- `/charly-selkies:selkies-desktop-layer` — Metalayer composing selkies with labwc, Chrome, waybar, desktop tools
- `/charly-distros:nvidia`, `/charly-distros:rocm` — GPU runtime candies feeding DRINODE into the selkies VAAPI encoder
- `/charly-selkies:ffmpeg` — Codec dep used by the capture bridge for H.264→PNG decode
- `/charly-coder:build-toolchain` — Builder-stage packages (smithay, bindgen, codec devel) that compile the patched pixelflux
- `/charly-distros:rpmfusion` — Applied before build-toolchain so codec devel libs (libva-devel, x264-devel, ffmpeg-devel) install

## Related Boxes

- `/charly-selkies:selkies-labwc`, `/charly-selkies:selkies-labwc-nvidia` — Boxes that bundle this candy
- `/charly-distros:arch-builder` — Builder image for the pixelflux from-source compilation (`cuda-arch-builder` on the GPU build)

## Related Commands

- `/charly-check:wl` — Wayland automation (screenshot via capture bridge, input, windows)
- `/charly-check:cdp` — Chrome DevTools and SPA bridge (click, type, key-combo through remote desktop)
- `/charly-check:record` — Desktop video recording via capture bridge
- `/charly-core:charly-update` — Per-instance update pattern used to roll out pixelflux memory fixes
- `/charly-core:charly-config` — DRINODE auto-injection, resource caps, NO_PROXY auto-enrichment, keyboard layout XKB env
- `/charly-core:charly-doctor` — Host GPU probe feeding `appendAutoDetectedEnv()` (DRINODE, HSA_OVERRIDE_GFX_VERSION)

## Security

- `shm_size: "1g"`

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
