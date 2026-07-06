---
name: vnc
description: |
  VNC/RFB desktop automation via the declarative `vnc:` check verb, served
  out-of-process by `candy/plugin-vnc` (covers pod AND vm targets).
  MUST be invoked before any work involving: the `vnc:` check verb, VNC
  automation, RFB protocol desktop interaction, VNC screenshots, clicking
  coordinates, or VNC authentication.
---

# VNC - VNC Desktop Automation

## Overview

The `vnc:` check verb connects to VNC servers (RFB protocol on port tcp:5900)
inside running containers — and to a VM's libvirt VNC display. It is **NOT a host
`charly check` subcommand** — it is a declarative check verb served out-of-process
by its plugin (`candy/plugin-vnc`), parallel to the `cdp:`/`mcp:`/`record:` plugin
verbs. Author a `vnc:` step in a candy/box plan and run it against a live
deployment with `charly check live <image> --filter vnc`. It provides screenshot
capture, keyboard/mouse input, and VNC password management for Wayland desktop
automation via wayvnc.

**Served out-of-process — covers pod AND vm targets.** The host dispatches the
`vnc:` verb through the provider registry exactly like a built-in
(`ResolveVerb("vnc")` → the out-of-process gRPC provider → `Provider.Invoke` with
the full `Op`). Before dialing, the host pre-resolves the RFB endpoint — a pod's
published port 5900, or a VM's libvirt VNC reached via bridge/tunnel — and the
plugin dials it and speaks RFB. ONE verb covers BOTH pod and vm targets — the two
former host CLI subcommands (a per-method pod form and a separate
`vnc vm <name> <method>` VM form) are gone. Authoring is unchanged from a built-in
verb: you write `vnc: screenshot`, never `plugin: vnc`.

### Authoring a `vnc:` step

Each method is the declarative `vnc:` step you author — an ordered list item under
the candy/box `plan:`. The method name
(status/screenshot/click/mouse/type/key/rfb/passwd) is the scalar value for a
bare-method step (`vnc: status`), or the `method:` key of the `vnc:` map when the step
carries vnc-exclusive fields (`x:`, `y:`, `button:`, `text:`, `key:`, `artifact:`,
`artifact_min_bytes:`, …) — those live INSIDE the `vnc:` map. Only the shared matchers
(`stdout:`, `stderr:`, `exit_status:`) and `context:`/`id:`/`timeout:` stay siblings.
All `vnc:` steps are **deploy-context only** (they need a running deployment), so
author them with `context: [deploy]`. See `/charly-check:check` for the full YAML
shape. Example:

```yaml
- check: a non-empty VNC framebuffer is captured
  context: [deploy]
  vnc:
    method: screenshot
    artifact: /tmp/vnc.png
    artifact_min_bytes: 5000
```

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Screenshot | `vnc: screenshot` + `artifact:` | Capture VNC framebuffer as PNG |
| Click | `vnc: click` + `x:` + `y:` | Click at x,y coordinates |
| Type text | `vnc: type` + `text:` | Send keyboard input as key events |
| Send key | `vnc: key` + `key:` | Press a special key (Return, Escape, etc.) |
| Move mouse | `vnc: mouse` + `x:` + `y:` | Move mouse without clicking |
| Status | `vnc: status` | Check VNC server, show resolution and desktop name |
| Set password | `vnc: passwd` | Set VNC auth password for deployment |
| Raw RFB | `vnc: rfb` | Send raw RFB protocol message |

The `+ <field>:` entries are keys INSIDE the `vnc:` map (`vnc: {method: click, x: …, y: …}`);
only `stdout:`/`stderr:`/`exit_status:` and `context:`/`id:`/`timeout:` are siblings.

Run a candy's baked `vnc:` steps against a live deployment with
`charly check live <image> --filter vnc` (add `-i <instance>` for multi-instance).

## Architecture

```
host (charly check live --filter vnc)
   -> vnc_preresolve.go: pre-resolve the RFB endpoint
        pod: podman port <name> 5900   |   vm: libvirt VNC via bridge/tunnel
   -> resolveVNCPassword (charly settings + VNC_PASSWORD env — retained host-side)
   -> Op + endpoint + password handed to candy/plugin-vnc over gRPC
candy/plugin-vnc
   -> NewVNCClient(address, password) -> RFB handshake -> operation
```

The host pre-resolves the dual pod/vm endpoint and the credential, then dispatches
the verb out-of-process. The custom RFC 6143 VNC client (no external dependency;
supports None, VNC auth (DES), and VeNCrypt (TLS + sub-auth) security types) lives
in `candy/plugin-vnc`. The host retains only the endpoint pre-resolution and
`resolveVNCPassword` (the VNC credential store).

## Requirements

- Container must include the `wayvnc` layer (port tcp:5900)
- Container must be running (`charly start`)
- Wayland compositor must be active (sway)

## Methods

Each method below is a `vnc:` plan step authored with `context: [deploy]`; run a
candy's baked steps with `charly check live <image> --filter vnc` (add
`-i <instance>` for a specific instance).

### Screenshot
```yaml
- check: a non-empty VNC framebuffer is captured
  context: [deploy]
  vnc:
    method: screenshot
    artifact: /tmp/desktop.png        # host path for the captured PNG
    artifact_min_bytes: 5000
```

### Click
```yaml
- run: left-click the desktop center (1920x1080)
  context: [deploy]
  vnc:
    method: click
    x: 960
    y: 540
```

The `vnc:` verb takes **desktop-absolute** `x:`/`y:`. To click an element located by
CSS selector, read its desktop coordinates from a `cdp: coords` step (it reports
both viewport and desktop coords) and author the `vnc: click` with those `x:`/`y:`
— see "Using CDP Coordinates with VNC" below. The sibling `wl: click` verb takes the
same desktop-absolute coords and is the Wayland-native alternative on a wlroots
desktop without VNC.

### Type
```yaml
- run: type each character as key events
  context: [deploy]
  vnc:
    method: type
    text: hello world
```
Only supports ASCII/Latin-1 characters. For special keys, use the `vnc: key` method.

### Key
```yaml
- run: press a special key
  context: [deploy]
  vnc:
    method: key
    key: Return            # also Escape, Tab, F5, Control_L, ...
```

Valid key names: Return, Escape, Tab, BackSpace, Delete, Home, End, Page_Up, Page_Down, Up, Down, Left, Right, Insert, F1-F12, Shift_L, Shift_R, Control_L, Control_R, Alt_L, Alt_R, Super_L, Super_R, Meta_L, Meta_R, Caps_Lock, space.

### Mouse
```yaml
- run: move the mouse without clicking
  context: [deploy]
  vnc:
    method: mouse
    x: 500
    y: 300
```

### Status
```yaml
- check: the VNC server reports its desktop and resolution
  context: [deploy]
  vnc: status
  stdout:
    contains: "1920x1080"
# Output: Desktop: sway / Resolution: 1920x1080
```

### Password (`vnc: passwd`)

```yaml
- run: provision VNC auth (VeNCrypt/TLS) for the deployment
  context: [deploy]
  vnc: passwd
```

The `vnc: passwd` method sets up VNC authentication (VeNCrypt/TLS):
1. Stores the password in the VNC credential store (system keyring or config file, depending on the `secret_backend` setting) as `vnc.password.<image>`
2. Resolves `$HOME` inside the venue for absolute config paths
3. Generates self-signed TLS cert+key (valid 3650 days) if not present
4. Generates RSA key in traditional format (`-traditional` flag for OpenSSL 3.x) if not present
5. Writes `~/.config/wayvnc/config` with `enable_auth=true` (wayvnc reads this automatically)
6. Restarts the wayvnc supervisord service

After a password is set, all `vnc:` operations authenticate transparently via VeNCrypt/TLS.

### Password Resolution Chain

When connecting, the password is resolved by the host-side credential store
(`resolveVNCPassword`, retained in core) in this order:
1. `VNC_PASSWORD` environment variable (CI/automation override)
2. System keyring lookup for `vnc.password.<image>-<instance>` (when `secret_backend=auto` or `keyring`)
3. Config file lookup for `vnc.password.<image>-<instance>` (instance-specific)
4. System keyring / config file lookup for `vnc.password.<image>` (image-level)
5. Empty string (no auth — server must allow unauthenticated connections)

```bash
# One-off password override via env (applies to the run)
VNC_PASSWORD=secret charly check live sway-browser-vnc --filter vnc

# Set password programmatically (alternative to the vnc: passwd step)
charly settings set vnc.password.sway-browser-vnc mysecret

# Instance-specific password
charly settings set vnc.password.sway-browser-vnc-prod prodpassword
```

Requires `openssl` inside the venue for TLS cert and RSA key generation.

### Raw RFB (`vnc: rfb`)

A `vnc: rfb` step sends a raw RFB protocol message (raw key/pointer/cut-text
events, framebuffer-update requests) for cases the typed methods above don't
cover — the RFB sub-method rides the `http_method:` field and its JSON payload rides
`params:`, both inside the `vnc:` map (the input's `method:` is always the verb method
`rfb`). Prefer the typed `vnc: click`/`type`/`key` methods; reach for `vnc: rfb` only
for low-level protocol work.

## Differences from CDP Commands

| Aspect | `cdp:` verb (CDP) | `vnc:` verb (RFB) |
|--------|----------------|----------------|
| Protocol | WebSocket JSON | Binary TCP |
| Scope | Browser tabs | Whole desktop |
| Click | CSS selector (viewport-relative) | x,y coordinates (desktop-absolute) |
| Type | CDP key events | Key events (keysyms) |
| Screenshot | Browser page only | Full desktop |
| JavaScript | Yes (check/wait) | No |
| Use case | Web automation | Desktop automation |

Source: `candy/plugin-vnc` (the out-of-process RFB client); host-side endpoint
pre-resolution + the VNC credential store in `charly/vnc_preresolve.go`.

## VNC as Anti-Detection Fallback

Some websites (notably Google sign-in) detect and block CDP-based input. VNC provides a reliable fallback because the `vnc:` verb's `type` method sends real X11 keysym events through the Wayland compositor — indistinguishable from physical keyboard input.

**CDP + VNC Hybrid Pattern:** Locate the element with a `cdp: coords` step (CDP selector precision — it reports the desktop coordinates), deliver the click with a `vnc: click` step at those desktop coords, and type credentials with a `vnc: type` step:

```yaml
# 1. Locate via cdp: coords — reports both viewport and desktop coords for '#identifierId'
- check: the email field is located
  context: [deploy]
  cdp:
    method: coords
    tab: "1"
    selector: "#identifierId"
# 2. Deliver the click via VNC at the reported desktop coords
- run: focus the email field via the VNC pointer
  context: [deploy]
  vnc:
    method: click
    x: 1166
    y: 421
# 3. Type real key events through the compositor
- run: type the email address
  context: [deploy]
  vnc:
    method: type
    text: "${ENV_GMAIL_USER}"
```

**Tested timing:** the compositor needs a moment between the VNC click and VNC type; author the type step after the click in plan order. No characters were dropped during Google sign-in testing.

When to use the VNC-delivered click and VNC type:
- **`chrome://` pages** (required): CDP mouse events and JS `.click()` are blocked on Chrome's privileged pages (`chrome://intro/`, `chrome://sync-confirmation/`, `chrome://settings/`). Delivering the click via VNC is the only way to click.
- Google sign-in or other anti-automation-protected forms
- Sites that validate input event sequences (keyDown/keyPress/input/keyUp)
- Any form where CDP type fails silently (value appears but form doesn't accept it)

**Chrome first-run dialogs:** On fresh profiles, Chrome opens a first-run dialog as a separate window invisible to CDP. Dismiss it by focusing it (a `wl: sway-focus` step) then pressing Return with a `vnc: key` step (`key: Return`).

See `/charly-check:cdp` for the full Google sign-in recipe.

## Using CDP Coordinates with VNC

The `vnc:` verb takes desktop-absolute coordinates, while CDP returns
viewport-relative coordinates. A **`cdp: coords`** step bridges them: it reports an
element's position in three systems — viewport, desktop (via `window.screenX/screenY`),
and desktop (via the sway tree) — so you author the `vnc: click` with the reported
desktop `x:`/`y:`:

```yaml
- check: the sync button is located
  context: [deploy]
  cdp:
    method: coords
    tab: "1"
    selector: "#sync-button"
# Viewport: x=1166 y=310  center=(1220, 328)
# Desktop:  x=1166 y=421  center=(1220, 439)   ← use these for vnc: click
- run: click the sync button via the VNC pointer
  context: [deploy]
  vnc:
    method: click
    x: 1220
    y: 439
```

The sibling `wl: click` verb takes the same desktop-absolute coords (the `cdp: coords`
step reports them), so on a wlroots desktop without VNC author a `wl: click` step with
the reported desktop `x:`/`y:` instead of `vnc: click`.

## NVIDIA Headless: VNC Screenshots Work

VNC screenshots work correctly on NVIDIA headless for images using `sway-desktop-vnc` (the standard VNC composition). Two fixes enable this:

1. **Pixman renderer** — `sway-desktop-vnc` forces `WLR_RENDERER=pixman` (software rendering), producing buffers wayvnc can reliably capture
2. **DPMS workaround** — `wayvnc-wrapper` triggers the missing headless power event that wayvnc 0.9.1 waits for before starting capture

Both the `vnc: screenshot` step and the `wl: screenshot` step (grim, always works) work on NVIDIA headless:
```yaml
- check: a non-empty VNC framebuffer is captured (works with pixman + DPMS fix)
  context: [deploy]
  vnc:
    method: screenshot
    artifact: /tmp/out.png
    artifact_min_bytes: 5000
- check: a non-empty Wayland screenshot is captured (grim)
  context: [deploy]
  wl:
    method: screenshot
    artifact: /tmp/wl-out.png
    artifact_min_bytes: 5000
```

## Cross-References

- `/charly-check:check` — parent router; the `vnc:` verb dispatches out-of-process via `candy/plugin-vnc` (the host pre-resolves the pod/vm RFB endpoint).
- `/charly-check:wl` — Wayland-native desktop automation (sibling verb; works on NVIDIA headless).
- `/charly-check:cdp` — Chrome DevTools Protocol automation (sibling verb; same container, different protocol).
- `/charly-check:dbus` — D-Bus calls and desktop notifications via the declarative `dbus:` verb served out-of-process by `candy/plugin-dbus`.
- `/charly-check:wl` — the `wl:` verb's sway-* methods for Sway compositor control (window management, workspaces)
- `/charly-core:charly-config` — VNC password storage, `secret_backend` setting, `migrate-secrets` command
- `/charly-core:service` — Managing wayvnc supervisord service
- `/charly-core:deploy` — VNC password setup in deployment workflows
- `/charly-core:shell` — Executing commands inside containers
- `/charly-image:layer` — wayvnc layer configuration (port tcp:5900)

## When to Use This Skill

**MUST be invoked** when the task involves VNC automation, the `vnc:` check verb, RFB protocol desktop interaction, VNC screenshots, clicking coordinates, or VNC authentication. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Desktop automation. Use for pixel-level interaction when CDP can't reach the element. See also `/charly-check:cdp` (DOM, preferred), `/charly-check:wl` (sway subgroup) (window).
