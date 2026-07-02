---
name: kde-selkies
description: >
  The KDE nested-compositor PRIMITIVE for the selkies streaming desktop —
  startplasma-wayland nested in pixelflux, de-SDDM, started by a supervisord
  poll-for-wayland-1 service. MUST be invoked before editing the kde-selkies
  candy or its kde-selkies-session wrapper.
---

# kde-selkies — KDE Plasma nested-compositor primitive (the KDE seam)

`kde-selkies` is the KDE analogue of the `labwc` candy: the swappable
nested-compositor primitive that renders a desktop into pixelflux's `wayland-1`.
It runs a FULL KDE Plasma Wayland session (`startplasma-wayland` =
kwin_wayland + plasmashell) nested in pixelflux, so selkies streams Plasma.

## Headless de-SDDM design (load-bearing)

`require: [selkies, kde-shell, pipewire, dbus]` — NOT `kde-desktop`. A pod has
no DRM seat, no SDDM, no `graphical.target`. So:

- ONE supervisord service `kde-selkies-session` (priority 12, `scope: user`,
  `%(ENV_HOME)s` exec — resolves for both supervisord pods AND systemd-user
  targets via `service_render.go`). **No `after: graphical-session.target`** —
  the wrapper's poll-for-`/tmp/wayland-1` IS the ordering primitive (identical to
  `labwc-wrapper`).
- `kde-selkies-session` waits for pixelflux's `wayland-1`, sets
  `WAYLAND_DISPLAY=wayland-1` (so kwin renders INTO pixelflux), then
  `exec dbus-run-session startplasma-wayland`. kwin creates `wayland-0` for
  Plasma's own clients.
- **Chrome:** this session script does NOT launch Chrome. The supervised
  `[program:chrome]` service in the shared `selkies-core` candy
  (`/charly-selkies:selkies-core` "Chrome supervision", `restart: always`) owns it for
  both selkies flavors — `chrome-wrapper` self-polls for the `wayland-0` client
  socket kwin publishes, so it needs no per-flavor handoff and supervisord
  relaunches Chrome if it self-exits during the startup-race. Chrome works headless
  under KDE.

This headless-no-seat path is exercised by the `check-selkies-kde-pod` bed:
`kde-selkies-session` RUNNING ≥20s, `https://:3000/` → 200, Chrome CDP
`/json/version` → 200, plus the deploy-scope `wl` KWin checks this candy ships.

## Encoder

`kde-selkies` sets NO `SELKIES_ENCODER` — pixelflux auto-detects at runtime
(VAAPI on an AMD/Intel renderD via libva-native; NVENC from the cuda-arch-builder
pixelflux on the `*-nvidia` box; x264 otherwise). So ONE kde-selkies candy
streams on every GPU config. The encoder identity is asserted per-box in the
GPU check beds, not here.

## Related

- `/charly-selkies:labwc` — the other nested-compositor primitive (the labwc seam).
- `/charly-selkies:kde-shell` — the SDDM-free Plasma session packages kde-selkies requires.
- `/charly-selkies:selkies-kde-desktop` — the flavor metalayer composing this.
- `/charly-distros:cachyos` — CachyOS/Arch base where the KDE Plasma stack lives.
