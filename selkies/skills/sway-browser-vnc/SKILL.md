---
name: sway-browser-vnc
description: |
  Minimal Sway desktop with VNC remote access and Chrome browser.
  Use when working with VNC desktop containers or testing the sway-desktop-vnc composition.
---

# sway-browser-vnc

Minimal Sway desktop with VNC (wayvnc on port 5900) and Chrome (CDP on port 9222).

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | agent-forwarding, sway-desktop-vnc, dbus, charly |
| Ports | 5900, 9222, 9224 |

## Quick Start

```bash
charly box build sway-browser-vnc
charly start sway-browser-vnc
charly status sway-browser-vnc          # Shows all probes: supervisord, cdp, dbus, charly, sway, vnc, wl
charly check live sway-browser-vnc --filter vnc   # run the candy's vnc: status / screenshot steps
charly check live sway-browser-vnc --filter wl    # desktop screenshot via the wl: screenshot step
```

## D-Bus and Notification Support

This box includes the `dbus` candy (D-Bus session bus) plus the `charly` candy, enabling:
- the `dbus:` check verb (`notify`/`list`/`call`/`introspect`) — D-Bus interaction served out-of-process by `candy/plugin-dbus`, driving the session bus with `gdbus`
- `charly cmd` — single command execution with desktop notification on completion
- `charly agent terminal` — typed persistent TTY sessions, input, snapshots, and transcripts
- `charly status` — supervisord, dbus, and charly probes

```yaml
# author dbus: steps in the plan, run with: charly check live sway-browser-vnc --filter dbus
notify-build-done:
    check: a desktop notification is delivered
    dbus: notify
    context: [deploy]
    text: Build Complete
    description: Image built successfully
list-services:
    check: the notifications service is on the session bus
    dbus: list
    context: [deploy]
    stdout:
        contains: org.freedesktop.Notifications
```
```bash
charly cmd sway-browser-vnc "make test"    # Notifies on completion (gdbus, host-side)
```

The notification daemon (swaync) is included via the sway-desktop metalayer.

## Overlays

Fullscreen overlays for recording (via wl-overlay, included in sway-desktop):

```yaml
# author overlay steps in the plan, run with: charly check live sway-browser-vnc --filter wl
show-title:
    check: a fullscreen title card is shown
    wl: overlay-show
    context: [deploy]
    type: text
    text: INTRO
    name: title
show-lower-third:
    check: a lower-third is shown
    wl: overlay-show
    context: [deploy]
    type: lower-third
    text: Speaker
    subtitle: Role
    name: lt
show-countdown:
    check: a 3-second countdown is shown
    wl: overlay-show
    context: [deploy]
    type: countdown
    seconds: 3
    name: cd
show-highlight:
    check: a highlight region is shown
    wl: overlay-show
    context: [deploy]
    type: highlight
    region: "430,290,510,50"
    name: hl
show-fade:
    check: a fade-to-black outro is shown
    wl: overlay-show
    context: [deploy]
    type: fade
    color: black
    name: outro
hide-all:
    check: all overlays are hidden
    wl: overlay-hide
    context: [deploy]
    all: true
```

All overlay types render with true RGBA compositor transparency. See `/charly-check:wl-overlay` for the full recording workflow.

## Recording

Desktop video recording via wf-recorder (included in sway-desktop) is authored as
`record:` plan steps (the declarative verb served out-of-process by `candy/plugin-record`)
and run with `charly check live sway-browser-vnc --filter record`:

```yaml
sway-rec-start:
    check: a desktop recording starts
    record: start
    context: [deploy]
    record_name: demo
    record_mode: desktop
sway-rec-stop:
    check: the desktop recording is captured
    record: stop
    context: [deploy]
    record_name: demo
    artifact: demo.mp4
```

## Use as Selkies Remote Desktop Client

sway-browser-vnc can act as a test client for selkies-desktop, simulating how a real user would connect via browser:

```bash
# Both containers must be running on the charly bridge network
charly start sway-browser-vnc
charly start selkies-desktop

# Open selkies URL in sway-browser-vnc's Chrome via a cdp: open step
# (the cdp: verb is served out-of-process by candy/plugin-cdp):
#   cdp: open  url: https://charly-selkies-desktop:3000
# Run with: charly check live sway-browser-vnc --filter cdp

# Interact with the remote desktop:
# Mouse: cdp: spa-click on the Selkies tab (with ~0.82x coordinate scaling)
# Keyboard: a vnc: type step (passthrough via SPA's overlayInput)
# Screenshots: a vnc: screenshot step (shows full client desktop with stream)
#              a cdp: screenshot step (shows only the stream content)
```

**Key limitations when using as a client:**
- Super key consumed by sway (can't trigger remote labwc keybinds like Super+e)
- Ctrl+T/W consumed by local Chrome (open/close tabs locally, not remotely)
- Clipboard permission dialog appears on first connection — dismiss with a `vnc: key` step (`key: Return`) or CDP `Browser.grantPermissions`

See `/charly-selkies:selkies-labwc` for detailed SPA interaction documentation.

## Test Coverage

Latest `charly check live sway-browser-vnc` run: **84 passed, 0 failed, 1 skipped**
(`chrome-devtools-mcp-port` references `${HOST_PORT:9224}` which isn't
mapped here — correct skip behavior).

Covers all 19 transitive candies: wayvnc (VNC), sway (compositor),
chrome-sway, xdg-portal, waybar, swaync, pavucontrol, thunar,
xfce4-terminal, pipewire, wl-screenshot-grim, wl-overlay, wf-recorder,
desktop-fonts, fastfetch, asciinema, tmux, dbus, charly. Deploy-scope: VNC
port 5900 reachable, Chrome CDP on port 9250→9222 with `/json/version`
200. Box-scope: sway + wayvnc both RUNNING under supervisord.

## Related Skills

- `/charly-selkies:sway-desktop-vnc`, `/charly-selkies:sway`, `/charly-selkies:wayvnc`,
  `/charly-selkies:chrome-sway`, `/charly-selkies:xdg-portal`, `/charly-infrastructure:dbus-layer`,
  `/charly-tools:charly`, `/charly-distros:agent-forwarding`
- `/charly-check:check` — declarative testing framework (parent router for the out-of-process live-container check verbs `wl:`/`cdp:`/`vnc:`/`mcp:`/`dbus:`)
- `/charly-check:vnc` — VNC automation on this box
- `/charly-check:cdp` — Chrome automation (CDP on host port 9250)
- `/charly-check:wl` — Wayland input/windows/clipboard (sway subgroup for compositor control)
- `/charly-check:dbus` — the `dbus:` check verb (notifications/list/call/introspect, served out-of-process by `candy/plugin-dbus`)
- `/charly-build:charly-mcp-cmd` — the box inherits 2 deploy-scope `mcp:` checks from the `chrome-devtools-mcp` candy (ping + list-tools asserting `navigate_page`/`take_screenshot`). `charly check live sway-browser-vnc --filter mcp` runs them; note the **port-publishing gotcha** — if your `charly.yml` has an explicit `port:` override that predates `chrome-devtools-mcp`, port 9224 may not be published. See `/charly-build:charly-mcp-cmd` for the fix.

## Related Boxes

- `selkies-desktop` — browser-accessible remote desktop (can be accessed from sway-browser-vnc's Chrome)

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
