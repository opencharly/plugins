---
name: selkies-kde-desktop
description: >
  The full KDE Plasma flavor of the selkies streaming desktop — a headless pod
  running startplasma-wayland (kwin_wayland + plasmashell) nested in pixelflux,
  the KDE sibling of the labwc selkies-desktop. MUST be invoked before working
  on the selkies-kde-desktop metalayer, the kde-selkies / kde-shell layers, the
  selkies-kde / selkies-kde-nvidia boxes, or their check beds.
---

# selkies-kde-desktop — KDE Plasma selkies streaming flavor

`selkies-kde-desktop` is the **KDE Plasma flavor** of the selkies streaming
desktop, the sibling of the labwc flavor (`selkies-desktop`). Both share one
transport core and differ ONLY in the nested compositor (R3 — no duplicated
streaming stack).

## Three-tier decomposition (shared with the labwc flavor)

- **`selkies-core`** — the compositor-agnostic streaming spine: the `selkies`
  transport (pixelflux owns `wayland-1` + capture-server + traefik:3000 +
  ffmpeg + pipewire) plus the shared fixings (chrome, chrome-cdp, desktop-fonts,
  wl-tools, wl-screenshot/record/overlay-pixelflux, a11y-tools, xterm, tmux,
  asciinema, fastfetch, sshd). NO compositor, NO panel/notifier.
- **`kde-selkies`** — the KDE nested-compositor PRIMITIVE (the swappable seam,
  analogous to `labwc`): `require: [selkies, kde-shell, pipewire, dbus]`; a
  single supervisord service (`kde-selkies-session`, priority 12, `scope: user`)
  that polls for `/tmp/wayland-1` then `exec dbus-run-session startplasma-wayland`.
- **`kde-shell`** — the SDDM-free Plasma SESSION package leaf (plasma-desktop
  deps-puller + kwin_wayland + plasmashell + the core session components +
  curated apps), shared by `kde-desktop` (bare-metal SDDM seat) and `kde-selkies`
  (headless pod). Workstation-only extras (kdeconnect, bluedevil, partition
  tools, kwallet, …) stay in `kde-desktop` so the streaming pod stays lean.
- **`selkies-kde-desktop`** (this metalayer) = `selkies-core` + `kde-selkies`
  (which pulls `kde-shell` transitively). KDE ships its own audio applet
  (plasma-pa) + panel + notifier, so there is NO waybar/swaync/pavucontrol here.

## De-SDDM: how Plasma runs headless as a pod (the load-bearing design)

A pod has no DRM seat, no SDDM, no `graphical.target`. `kde-selkies` therefore
runs `startplasma-wayland` directly under a supervisord poll-for-`wayland-1`
service — **no `after: graphical-session.target`**, no display manager. kwin
renders INTO pixelflux's `wayland-1` and creates `wayland-0` for Plasma's own
clients. This headless-no-seat path is PROVEN on a real pod (`check-selkies-kde-pod`:
`kde-selkies-session` RUNNING ≥20s, `https://:3000/` → 200, full live-check pass).

**Chrome is a supervised `selkies-core` service.** Chrome is launched and
supervised by the `[program:chrome]` supervisord service defined in `selkies-core`
(shared by both flavors — labwc and KDE) — NOT by `kde-selkies-session` and not
by the compositor autostart. The service runs `chrome-wrapper` with
`WAYLAND_DISPLAY=wayland-0`, `restart: always` (relaunches on any exit, including
the clean exit 0 of the nested-compositor startup race), `start_secs: 5` +
`start_retries: 3` (the single >5s startup-race self-exit resets the retry budget
so it never trips FATAL), and `priority: 30`. `autostart` defaults true and is
self-synchronizing — `chrome-wrapper` itself polls for the `wayland-0` client
socket that kwin publishes, so no per-flavor handoff is needed. Chrome works
headless under KDE; `cdp-proxy` proxies its CDP backend.

## Encoder is auto-selected at runtime (one box, every GPU config)

pixelflux picks the H.264 encoder at runtime from the host render node — it uses
**libva directly (NOT gstreamer; no gst-vaapi element is installed)**:

- **AMD / Intel render node** (`DRINODE=/dev/dri/renderD*`, auto-injected) →
  hardware **VAAPI** (Mesa radeonsi; `vainfo` shows `VAProfileH264*:
  VAEntrypointEncSlice`). So the **cachyos base image VAAPI-encodes on an AMD/Intel
  host** — "CPU" and "AMD" are the SAME box, not two.
- **No usable render node** → software **x264**.
- **NVIDIA** → **NVENC**, but only from the `*-nvidia` box whose pixelflux is
  built un-stubbed against the `cuda-arch-builder` (the cachyos GPU base's
  pixelflux stubs NVENC). NVENC is proven INSIDE the GPU-passthrough VM (the
  RTX-class card is vfio-bound, invisible to a host pod), never as a host pod.

## Images + test venues

| Box | Base | Encoder venue |
|---|---|---|
| `selkies-kde` | cachyos | host pod → VAAPI (AMD/Intel) or x264 (`check-selkies-kde-pod`) |
| `selkies-kde-nvidia` | cachyos.nvidia (cuda-arch-builder) | nested pod in the GPU-passthrough VM → NVENC (`check-selkies-kde-nvidia-vm`, `requires_exclusive: [nvidia-gpu]`) |

The labwc sibling (`selkies-labwc` / `selkies-labwc-nvidia`) mirrors this exactly
on the `selkies-desktop` metalayer.

## Related

- `/charly-selkies:selkies` — the pixelflux/selkies streaming transport (the core).
- `/charly-selkies:selkies-desktop-layer` — the labwc sibling flavor.
- `/charly-selkies:labwc` — the labwc nested-compositor primitive (the other seam).
- `/charly-distros:cachyos`, `/charly-distros:nvidia` — the CPU + GPU bases.
- `/charly-check:check` — the disposable check beds (`disposable: true` deploys) that prove each flavor.
- `/charly-internals:disposable` — `requires_exclusive`/`preemptible` (the GPU-VM bed
  preempts the operator workstation for the single passthrough GPU).
