---
name: selkies-labwc
description: |
  The labwc flavor of the Selkies streaming desktop (cpu/default GPU build) — a
  browser-accessible Wayland desktop streamed via pixelflux WebSocket on the CachyOS base.
  MUST be invoked before building, deploying, or troubleshooting the selkies-labwc box.
---

# Box: selkies-labwc

The **labwc flavor** of the selkies streaming desktop — a browser-accessible Wayland desktop streamed via Selkies/pixelflux WebSocket at `https://localhost:3000` (HTTPS with self-signed Traefik certificate). It is the symmetric sibling of the KDE Plasma flavor (`/charly-selkies:selkies-kde-desktop`); both compose the shared `/charly-selkies:selkies-core` spine and differ only in the compositor candy (`labwc` here, `kde-selkies` there). Always runs as a headless pod; the pixelflux encoder is auto-selected per GPU at runtime (VAAPI / NVENC / x264).

## Definition

```yaml
selkies-labwc:
  base: cachyos               # local cachyos base (same box/cachyos submodule)
  build: [pac, aur]          # aur required: chrome (google-chrome) + wl-tools (wlrctl)
  candy:
    - agent-forwarding
    - selkies-desktop
    - dbus
    - charly
  ports:
    - "3000:3000"
    - "9222:9222"
    - "9224:9224"
  platforms:
    - linux/amd64
```

Tunnel config is in `charly.yml`: `tunnel: {provider: tailscale, private: all}`. See `/charly-core:deploy`.

## Base

`cachyos` — the Arch-derived, x86_64_v3-optimized base, a local sibling box in
the same `opencharly/distro-cachyos` submodule (`box/cachyos`) that owns this box.
Multimedia codecs (ffmpeg, x264, libva) come from Arch's `extra` repo; Chrome
installs from the AUR (`google-chrome`). The box declares `build: [pac, aur]`
so the AUR builder compiles `google-chrome` (chrome candy) and `wlrctl`
(wl-tools layer); inheriting plain `[pac]` would silently skip both. Because a
`builder:` map does NOT cross a namespace boundary, the box declares its OWN
`builder:` map (pixi/npm/cargo/aur → `arch.arch-builder`, the builder the
`opencharly/distro-arch` submodule provides through the `arch` import namespace) rather
than inheriting one from the cachyos base. The GPU sibling (`selkies-labwc-nvidia`, in the same submodule)
is the same `selkies-desktop` metalayer on the CachyOS GPU base (`cachyos.nvidia`),
with `builder.pixi: arch.cuda-arch-builder` so the selkies candy compiles
pixelflux's real NVENC encoder.

## Layers

`agent-forwarding` (gnupg + direnv + ssh-client) + `selkies-desktop` metalayer (pipewire + chrome + labwc + waybar-labwc + desktop-fonts + swaync + pavucontrol + wl-tools + wl-screenshot-pixelflux + wl-overlay + wl-record-pixelflux + a11y-tools + xterm + tmux + asciinema + fastfetch + selkies) + `dbus` + `charly`

## Ports

| Port | Service |
|------|---------|
| 3000 | Selkies web UI (Traefik HTTPS → static files + WebSocket proxy) |
| 9222 | Chrome DevTools Protocol (CDP, via cdp-proxy) |
| 9224 | Chrome DevTools MCP (Streamable HTTP, via chrome-devtools-mcp) |

## Access

Open `https://localhost:3000` in a browser. Accept the self-signed certificate warning (Traefik auto-generates a cert with SANs for localhost, selkies.localhost, and charly-selkies-labwc). The Selkies dashboard shows the labwc desktop with Chrome and Waybar at the top.

HTTPS is required for the WebCodecs API (`VideoDecoder`) used by the Selkies JS client. From other containers on the same network, use `https://charly-selkies-labwc:3000`.

## Quick Start

```bash
charly box build selkies-labwc
charly config selkies-labwc
charly start selkies-labwc
# Access: https://localhost:3000 (accept cert warning)
charly check live selkies-labwc --filter wl    # desktop screenshot via the wl: screenshot step
```

## Keyboard Configuration

Override the default US keyboard layout via environment variables:

```bash
charly config selkies-labwc -e XKB_DEFAULT_LAYOUT=de                              # German QWERTZ
charly config selkies-labwc -e XKB_DEFAULT_LAYOUT=fr -e XKB_DEFAULT_VARIANT=nodeadkeys  # French, no dead keys
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `XKB_DEFAULT_LAYOUT` | `us` | Keyboard layout |
| `XKB_DEFAULT_VARIANT` | (empty) | Layout variant |
| `XKB_DEFAULT_MODEL` | `pc105` | Keyboard model |
| `XKB_DEFAULT_OPTIONS` | (empty) | XKB options |

All level 0/1 characters (ö, ä, ü, ß, =, ?) and AltGr characters (@, €, \\, ~) work for any layout. See `/charly-selkies:labwc` for details and `/charly-selkies:selkies` for the input pipeline.

## Services

| Service | Priority | Purpose |
|---------|----------|---------|
| `selkies` | 8 | Wayland capture + H.264/Opus streaming via pixelflux |
| `traefik` | 18 | HTTPS reverse proxy on port 3000 |
| `selkies-fileserver` | 19 | Static file server for web UI |
| `labwc` | 12 | Wayland compositor (nested in pixelflux) |
| `waybar` | 15 | Status bar |
| `swaync` | 14 | Notification daemon |
| `pipewire` | 5 | Audio server |
| `dbus` | 2 | D-Bus session bus |
| `cdp-proxy` | — | CDP reverse proxy (Host header + URL rewrite for Chrome 146+) |

## GPU Support

- **Rendering:** NVIDIA GPU via CDI, AMD/Intel via Mesa. `DRINODE`/`DRI_NODE` auto-detected at runtime by `charly config` (from first `/dev/dri/renderD*`)
- **VAAPI encoding (AMD):** Hardware H264 encoding via VAAPI — requires correct DRINODE (auto-detected). Wrong DRINODE causes CPU fallback → swapchain buffer exhaustion → stream flickering
- **NVENC (NVIDIA):** Detected but currently fails with driver 590.48 (pixelflux compat issue). Falls back to CPU x264enc
- **CPU fallback:** x264enc-striped at 60fps (16 parallel stripes) — works but may cause flickering at high resolutions due to compositor buffer pressure

## Volumes

- `chrome-data` → `~/.chrome-debug` (Chrome profile)
- `selkies-config` → `~/.config/selkies`

## Known Issues

1. **NVENC encoding fails** with NVIDIA driver 590.48 — pixelflux detects GPU, CUDA inits, but encoder init fails. CPU encoding works fine.
2. **Chrome volume permissions** — first deploy may need `podman unshare chown 1000:1000 $(charly volume list selkies-labwc | awk '/chrome-data/{print $2}')` — provisioning-time ownership is a queued charly gap``
3. **Audio** — PulseAudio null sinks created by selkies-wrapper. Audio streaming works but may have slight latency over WebSocket.

## Screenshots and Recording

The capture bridge provides the `wl:` verb's `screenshot` method and the declarative `record:`
check verb (served out-of-process by `candy/plugin-record`):

```bash
# Desktop screenshot via the wl: screenshot step (works with or without browser connected)
charly check live selkies-labwc --filter wl

# Check bridge status
charly shell selkies-labwc -c "pixelflux-screenshot --status"
```

Desktop video recording (with audio via PulseAudio) is authored as `record:` plan steps
and run with `charly check live selkies-labwc --filter record`:

```yaml
labwc-rec-start:
    check: a desktop recording with audio starts
    record: start
    context: [deploy]
    record_name: demo
    record_mode: desktop
    record_audio: true
labwc-rec-stop:
    check: the desktop recording is captured
    record: stop
    context: [deploy]
    record_name: demo
    artifact: demo.mp4
```

The bridge auto-heals: if no valid H.264 frames are available (e.g., after browser disconnect), it reconnects as controller to restart the pipeline.

## Client-Side Interaction (Browser-Based Remote Desktop)

When accessing selkies-labwc from another container (e.g., `sway-browser-vnc`) or an external browser, the Selkies SPA provides full mouse and keyboard passthrough via WebSocket.

### SPA DOM Structure

The SPA renders the remote desktop on a `<canvas id="videoCanvas">` with an invisible input overlay that captures all events:

| Element | z-index | pointer-events | Purpose |
|---------|---------|---------------|---------|
| `div.status-display` | 5 | auto | Status bar (hidden by default) |
| `input#overlayInput` | 3 | auto | Transparent input overlay — captures all mouse + keyboard events |
| `canvas#videoCanvas` | 2 | **none** | H.264 video render surface (WebCodecs VideoDecoder → canvas) |
| `button#playButton` | 10 | auto | Play button (hidden after stream starts) |

**Header controls** (fullscreen, gaming mode) slide in from the left edge (`left: -132px`). Move the mouse to the left edge to reveal them.

### Coordinate Scaling

The SPA maps mouse events from the canvas viewport to the remote desktop with a scaling factor. When the canvas is 1908x950 and the remote desktop runs at a different resolution, there is an empirical **~0.824x / 0.836y** ratio between input coordinates and where the remote cursor lands.

Use a `cdp: spa-click` step (the `cdp:` verb is served out-of-process by candy/plugin-cdp); the SPA methods apply the scale correction automatically:

```yaml
# Click at canvas position (990, 375) with scale correction
spa-click:
    run: click at canvas coords
    cdp: spa-click
    context: [deploy]
    tab: "1"
    x: 990
    y: 375
```

### Keyboard Passthrough

**Recommended:** Use the `cdp: spa-*` steps for keyboard interaction — they bypass the local compositor and Chrome shortcut handlers (see `/charly-check:check` for the precise SPA-method modifier shape):

```yaml
# Type text (no double-char issue, bypasses local shortcuts)
spa-type:
    run: type text
    cdp: spa-type
    context: [deploy]
    tab: "1"
    text: hello world
# Send modifier combos that reach the REMOTE desktop:
spa-super-e:
    run: super+e — open foot terminal in labwc (also ctrl+t / alt+f4)
    cdp: spa-key-combo
    context: [deploy]
    tab: "1"
    text: super+e
# Send special keys:
spa-return:
    run: return (also escape)
    cdp: spa-key
    context: [deploy]
    tab: "1"
    text: return
```

**Alternative methods** (limited — local compositor/Chrome may intercept keys): a
`vnc: type` step (VNC keysym events) or a `wl: type` step
(wtype via Wayland) — both hit the same limitation (the Super key is intercepted by
the local compositor).

The SPA's `onkeydown` handler on `#overlayInput` intercepts events with `stopImmediatePropagation()`, converts to keysyms, and sends via WebSocket to the remote labwc compositor.

### Known Limitations (Browser-Based RD)

1. **Coordinate scaling requires `--scale` flag** — auto-detection not yet implemented. Determine the scale empirically by comparing cursor position with target.
2. **Clipboard permission dialog** — On first connection, Chrome prompts "charly-selkies-labwc:3000 wants to See text and images copied to the clipboard". Click Allow or dismiss via keyboard/CDP (`Browser.grantPermissions`).
3. **Closing the last tab exits Chrome** — If the client browser's last tab (the Selkies tab) is closed, Chrome exits. The client container may need a restart to recover Chrome.

### Session Resilience

The remote labwc desktop and all its applications **survive client disconnection**. When the browser tab is closed or the client container restarts, the selkies capture bridge auto-switches from viewer mode to controller mode. On reconnect, the SPA resumes streaming the same desktop state — all windows, typed text, and application state are preserved.

Chrome remembers the self-signed cert exception in the `chrome-data` volume, so no cert re-prompt on reconnect.

### Inter-Container Access

From another container on the `charly` bridge network:

```bash
# URL: https://charly-selkies-labwc:3000
# TLS cert SAN includes DNS:charly-selkies-labwc
# Verify connectivity:
curl -kso /dev/null -w '%{http_code}' https://charly-selkies-labwc:3000/
# Expected: 200

curl -kso /dev/null -w '%{http_code}' https://charly-selkies-labwc:3000/websockets
# Expected: 426 (WebSocket Upgrade Required — correct, not an error)
```

### Streaming Health Checks

```bash
# From within the client browser tab (via CDP check):
# Check canvas dimensions (non-zero = stream active)
document.getElementById("videoCanvas").width   // e.g., 1908
document.getElementById("videoCanvas").height  // e.g., 950

# Check secure context (required for WebCodecs)
window.isSecureContext                         // true

# Check decoder availability
typeof VideoDecoder !== "undefined"            // true (H.264)
typeof AudioDecoder !== "undefined"            // true (Opus)
```

## Deploy with Tailscale Exit Node

Route all outbound internet traffic (Chrome browsing) through a Tailscale exit node while keeping the desktop accessible on the host's tailnet and the charly bridge.

### Prerequisites

1. A Tailscale auth key for the sidecar's tailnet (can be a different tailnet from the host)
2. An exit node device advertising on that tailnet (approved in admin console)

### Setup

```bash
# Store auth key
charly secrets gpg set TS_AUTHKEY tskey-auth-xxxxxxxxxxxx
charly secrets gpg set TS_EXIT_NODE 100.80.254.4    # exit node's Tailscale IP

# Deploy with sidecar
charly config selkies-labwc --sidecar tailscale \
  -e TS_HOSTNAME=selkies-labwc \
  -e "TS_EXTRA_ARGS=--exit-node=${TS_EXIT_NODE} --exit-node-allow-lan-access"
charly start selkies-labwc

# First time: set exit node inside sidecar (persists in state volume)
charly cmd selkies-labwc --sidecar tailscale \
  "tailscale set --exit-node=100.80.254.4 --exit-node-allow-lan-access"
```

### Verify Dual Networking

```bash
# Exit node routing — shows exit node's public IP, not host's
charly cmd selkies-labwc "curl -s ifconfig.me"

# Bridge connectivity — other charly containers reachable
charly cmd selkies-labwc "getent hosts charly-ollama"

# Host tailnet — accessible via host's tailscale serve
curl -sk https://o.armadillo-quail.ts.net:3000/ | head -1

# Sidecar status
charly cmd selkies-labwc --sidecar tailscale "tailscale status"
```

### Architecture

The pod has dual networking: `Network=charly` (bridge for container-to-container) + `tailscale0` (tun interface for exit node). `--exit-node-allow-lan-access` adds `throw 10.89.0.0/24` to exempt bridge traffic. The charly.yml `tunnel: tailscale` config generates `ExecStartPost=tailscale serve` to expose ports 3000+9222 on the host's tailnet independently.

**Known issues:**
- `TS_DEBUG_FIREWALL_MODE=nftables` is required (iptables-legacy fails in rootless podman) — built into the sidecar template
- `ShmSize=1g` is required for Chrome — automatically propagated to the pod via `PodmanArgs=--shm-size`
- Exit node device must be **approved** on the sidecar's tailnet admin console
- First-time exit node: use `tailscale set --exit-node` inside sidecar (persists in state volume for restarts)

See `/charly-automation:sidecar` for full sidecar documentation.

## Multi-Instance Proxy Deployment

Deploy multiple instances with different HTTP proxies for IP-diverse browsing. Each instance gets unique host ports and its own MCP server (`chrome-devtools-<instance>`).

```bash
# Deploy 3 instances with different proxies (ports 3001-3003, CDP 9231-9233)
charly config selkies-labwc -i 45.39.130.21 \
  -e HTTP_PROXY=http://45.39.130.21:6753 \
  -e HTTPS_PROXY=http://45.39.130.21:6753 \
  -e 'NO_PROXY=localhost,127.0.0.1' \
  -p 3001:3000 -p 9231:9222

# Propagate MCP to hermes, then start
charly config hermes --update-all
charly start selkies-labwc -i 45.39.130.21

# Verify proxy IP — author a cdp: open step (url: https://httpbin.org/ip) and run:
charly check live selkies-labwc -i 45.39.130.21 --filter cdp
```

**Tailscale access (no sidecar needed):** The charly.yml `tunnel: tailscale` config generates `tailscale serve` commands for host-mapped ports. All instances are accessible via the host's Tailscale IP on their respective ports (`https://<host>:3001`, etc.). Use sidecars only when per-instance exit node routing is needed.

**MCP auto-disambiguation:** Each instance provides `chrome-devtools-<instance>` MCP server. Consumers (hermes) receive all instances in `CHARLY_MCP_SERVERS` JSON after `--update-all`.

See `/charly-core:charly-config` for `--update-all` propagation, `/charly-selkies:chrome` for `env_accept` (HTTP_PROXY/HTTPS_PROXY/NO_PROXY).

## Build Pipeline Note

The selkies-labwc box compiles `pixelflux_wayland` from source in the pixi
builder stage (`arch-builder` on the cachyos base; `cuda-arch-builder` on the GPU
build, `cachyos.nvidia`). This is because pixelflux's upstream wheel does not include the
**dmabuf cache cleanup fix** (`renderer.cleanup_texture_cache()` per frame) that
prevents a Wayland compositor shmem leak under sustained heavy streaming. The patch is
applied at build time via inline source patching in `candy/selkies/build.sh`. See
`/charly-selkies:selkies` (Patched pixelflux build pipeline) for the full pipeline and the
diagnostic recipe that found the leak.

## Related Boxes

- `/charly-selkies:selkies-labwc-nvidia` — the GPU sibling of this CPU box: the same `selkies-desktop` metalayer on the CachyOS GPU base (`cachyos.nvidia`, `build: [pac, aur]`) with `builder.pixi: arch.cuda-arch-builder` for real NVENC, in the `opencharly/distro-cachyos` submodule. See `/charly-distros:cachyos`.
- `/charly-openclaw:openclaw-desktop` — all-in-one CachyOS variant: this streaming desktop fused with the openclaw-full gateway + AI CLIs, a CPU ollama, and the full charly toolchain (build boxes, run nested pods, launch rootless libvirt VMs from inside the streaming desktop). Uses `/charly-distros:container-nesting`'s `unmask=/proc/*` posture — no `--privileged`, still uid 1000.
- `/charly-selkies:sway-browser-vnc` — VNC-based alternative using Sway compositor instead of Selkies/labwc streaming

## Verification

```bash
charly status selkies-labwc              # All services RUNNING
curl -k https://localhost:3000         # HTTPS 200, Selkies dashboard HTML
charly check live selkies-labwc --filter wl    # desktop screenshot via the wl: screenshot step (capture bridge)
charly check live selkies-labwc --filter cdp   # cdp: status — CDP available on port 9222
```

## Test Coverage

Latest `charly check live selkies-labwc` run: **91 passed, 0 failed, 0 skipped**
— the largest test suite in the project. Covers all 21 transitive
candies (selkies, chrome, sshd, chrome-devtools-mcp primary; labwc,
waybar-labwc, pipewire, swaync, pavucontrol, wl-tools, wl-*-pixelflux,
a11y-tools, xterm, desktop-fonts, asciinema, fastfetch, tmux
secondary).

Deploy-scope: ports 3000 (HTTPS selkies), 9222 (Chrome CDP), 9224
(chrome-devtools-mcp), 2222 (sshd) all reachable via
`127.0.0.1:${HOST_PORT:N}`. `/json/version` returns 200 with
`webSocketDebuggerUrl`. All primary services RUNNING under supervisord
(labwc, selkies, traefik, chrome via event-listener handoff, sshd).

Note: the sshd candy uses `sudo -n -l` rather than `file:` existence
for `/etc/sudoers.d/charly-user` because it's root-only (`/charly-check:check` Gotcha #10).

## Related Skills

- `/charly-selkies:selkies-desktop-layer` (metalayer), `/charly-selkies:selkies`,
  `/charly-selkies:chrome`, `/charly-selkies:labwc`, `/charly-coder:sshd`,
  `/charly-selkies:chrome-devtools-mcp`, `/charly-selkies:pipewire`
- `/charly-check:check` — declarative testing framework + testing gotchas
- `/charly-check:cdp`, `/charly-check:wl` — desktop automation on this box
- `/charly-core:charly-config` — deploy setup (tunnel, port remapping, instances)
- `/charly-build:charly-mcp-cmd` — the box bundles `chrome-devtools-mcp` (transitively via the chrome metalayer), so 2 deploy-scope `mcp:` checks (`ping`, `list-tools`) run against its MCP server on port 9224. `charly check live selkies-labwc --filter mcp` runs them, enumerating the 29 chrome-devtools tools.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
