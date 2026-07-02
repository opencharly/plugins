---
name: selkies-kde
description: |
  The KDE Plasma flavor of the Selkies streaming desktop (cpu/default GPU build) —
  a browser-accessible, headless-pod Wayland desktop running startplasma-wayland
  nested in pixelflux. MUST be invoked before building, deploying, or
  troubleshooting the selkies-kde box.
---

# Box: selkies-kde

The **full KDE Plasma flavor** of the selkies streaming desktop — a
browser-accessible Wayland desktop streamed via Selkies/pixelflux WebSocket at
`https://localhost:3000` (HTTPS, self-signed Traefik cert). It is the symmetric
sibling of the labwc flavor (`/charly-selkies:selkies-labwc`); both compose the shared
`/charly-selkies:selkies-core` spine and differ ONLY in the nested compositor (KDE
Plasma here via `/charly-selkies:kde-selkies`, labwc there). Always a **headless pod**
— de-SDDM `startplasma-wayland` nested in pixelflux, with no logind seat and no
SDDM (see `/charly-selkies:selkies-kde-desktop` for that load-bearing design). The
pixelflux encoder is auto-selected per GPU at runtime (VAAPI on an AMD/Intel
render node, software x264 otherwise; the `selkies-kde-nvidia` sibling adds NVENC).

Owned by the `opencharly/distro-cachyos` submodule (`box/cachyos`).

## Definition

```yaml
selkies-kde:
  base: cachyos              # plain CachyOS base (x86_64_v3 Arch derivative)
  build: [pac, aur]          # aur: chrome (google-chrome) + wl-tools (wlrctl)
  candy:
    - agent-forwarding
    - selkies-kde-desktop    # the KDE metalayer (selkies-core + kde-selkies → kde-shell)
    - dbus
    - charly
  port: ["3000:3000", "9222:9222", "9224:9224", "2222:2222"]
  platform: [linux/amd64]
```

## Ports

| Port | Service |
|------|---------|
| 3000 | Selkies web UI (Traefik HTTPS → static files + WebSocket proxy) |
| 9222 | Chrome DevTools Protocol (CDP) |
| 9224 | Chrome DevTools MCP (Streamable HTTP) |
| 2222 | sshd |

## Encoder (per-GPU, auto-selected at runtime)

- **VAAPI (AMD/Intel):** hardware H264 via the render node (the `selkies` candy
  ships `libva-mesa-driver`); `DRINODE` auto-detected by `charly config`.
- **CPU fallback:** x264 software encoding.
- **NVENC:** NOT on this box — use `/charly-selkies:selkies-kde-nvidia` (the CachyOS
  GPU build with the real NVENC-compiled pixelflux).

## Quick Start

```bash
charly -C box/cachyos box build selkies-kde
charly config selkies-kde
charly start selkies-kde
# Access: https://localhost:3000 (accept the self-signed cert)
charly check live selkies-kde --filter wl    # run the candy's wl: screenshot step
```

## Verification

- `charly check box selkies-kde` — build-scope (binaries: `plasmashell`, `kwin_wayland`, chrome, selkies).
- `charly check run check-selkies-kde-pod` — the disposable R10 bed: compositor renders
  (plasmashell + kwin_wayland present, `wayland-0` up), live :3000 stream
  (traefik HTTPS + capture STATUS-socket `frames>0`), `kde-selkies-stable` ≥20s uptime.

## Related Skills

- `/charly-selkies:selkies-kde-desktop` — the KDE metalayer + the de-SDDM headless-Plasma design (the load-bearing detail).
- `/charly-selkies:kde-selkies`, `/charly-selkies:kde-shell` — the KDE compositor primitive + the SDDM-free Plasma package leaf.
- `/charly-selkies:selkies-labwc` — the labwc sibling flavor (same streaming core; the canonical home of the shared SPA-interaction / CDP / wl-automation docs).
- `/charly-selkies:selkies-kde-nvidia` — the GPU build of this flavor (real NVENC).
- `/charly-selkies:selkies` — the pixelflux streaming transport.
- `/charly-distros:cachyos` — the CachyOS base + submodule.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries with `base:`/`from:`, build/validate/inspect/list).
- `/charly-build:build` — the embedded build vocabulary in `charly/charly.yml` (distros, builders, init-systems).
