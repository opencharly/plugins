---
name: selkies-core
description: >
  The compositor-agnostic core of the selkies streaming desktop — the pixelflux
  transport plus the shared desktop fixings consumed by BOTH flavors (labwc and
  KDE Plasma). MUST be invoked before editing the selkies-core metalayer or
  reasoning about what is shared vs flavor-specific in the selkies stack.
---

# selkies-core — shared streaming spine for all selkies flavors

`selkies-core` is the single shared metalayer underneath every selkies
streaming-desktop flavor. It exists so the WebRTC transport + the
compositor-agnostic desktop fixings are defined EXACTLY ONCE (R3) and the only
thing a flavor adds is its nested compositor.

## Composition

```
selkies-core =
  selkies            # pixelflux (owns wayland-1) + capture-server + traefik:3000 + ffmpeg
  pipewire           # audio (PulseAudio compat)
  chrome + chrome-cdp # browser + CDP proxy / chrome-devtools-mcp
  desktop-fonts
  wl-tools           # wtype/wlrctl/xdotool/wl-clipboard/wlr-randr
  wl-screenshot-pixelflux + wl-record-pixelflux + wl-overlay  # capture-bridge tooling
  a11y-tools         # AT-SPI2 introspection
  xterm tmux asciinema fastfetch
  sshd
```

There is **NO compositor and NO compositor-specific panel/notifier** in
selkies-core — those live in the per-flavor metalayer:

- `selkies-desktop` (labwc flavor) = `selkies-core` + `labwc` + `waybar-labwc` +
  `swaync` + `pavucontrol`.
- `selkies-kde-desktop` (KDE flavor) = `selkies-core` + `kde-selkies` (Plasma
  ships its own plasma-pa / panel / notifier, so no waybar/swaync/pavucontrol).

## Why this exists

Before the flavor split, `selkies-desktop` bundled the transport + the 13
fixings + labwc together, so a second flavor (KDE) would have duplicated all 13.
Factoring `selkies-core` out makes the nested compositor the ONLY swappable seam
between flavors (the `labwc` vs `kde-selkies` candy), across every GPU config
(the encoder is auto-selected at runtime by pixelflux — see
`/charly-selkies:selkies-kde-desktop` "Encoder is auto-selected").

## Chrome supervision

selkies-core owns the **supervised `[program:chrome]` supervisord service** that
runs the streaming desktop's browser for BOTH flavors — declared in
`candy/selkies-core/charly.yml`'s `service:` block, so labwc and KWin share one
launcher (R3). Fields: `restart: always` relaunches Chrome on any exit (including
the clean self-exit a Chrome started during the nested compositor's startup-race
produces — the relaunch lands post-settle, where Chrome stays up); `autostart`
defaults true and is **self-synchronizing** because `chrome-wrapper` polls for the
`wayland-0` client socket itself (no per-flavor `supervisorctl start` handoff);
`start_secs: 5` + `start_retries: 3` let the one startup-race exit reset the retry
budget rather than trip `FATAL`; `priority: 30`; `env WAYLAND_DISPLAY=wayland-0`.

Because selkies-core owns Chrome, the per-flavor compositor autostarts
(`candy/labwc/autostart`, `candy/kde-selkies/kde-selkies-session`) do NOT launch
it. `sway-browser-vnc` is NOT a selkies flavor (it uses the `chrome-sway` candy,
not selkies-core, and is not pixelflux-nested) and is unaffected. There is no
Chrome eventlistener / crash-listener; a wedged crash loop is cleared by
restarting the container (see `/charly-selkies:chrome` "Chrome supervision").

## Related

- `/charly-selkies:selkies` — the pixelflux transport at the heart of the core.
- `/charly-selkies:selkies-desktop-layer` — the labwc flavor metalayer.
- `/charly-selkies:selkies-kde-desktop` — the KDE Plasma flavor metalayer.
- `/charly-image:layer` — candy authoring; the unified `service:` schema.
