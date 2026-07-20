---
name: cdp
description: |
  Chrome DevTools Protocol browser automation via the declarative `cdp:` check
  verb, served out-of-process by `candy/plugin-cdp`.
  MUST be invoked before any work involving: the `cdp:` check verb, Chrome
  DevTools Protocol, browser automation, clicking elements, taking screenshots,
  or OAuth flows inside containers.
---

# CDP - Chrome DevTools Protocol

## Overview

The `cdp:` check verb connects to Chrome DevTools Protocol (CDP) on port 9222
inside running containers. It is **NOT a host `charly check` subcommand** — it is
a declarative check verb served out-of-process by its plugin (`candy/plugin-cdp`),
parallel to the `mcp:`/`record:`/`adb:`/`appium:` plugin verbs. Author a `cdp:` step
in a candy/box plan and run it against a live deployment with
`charly check live <image> --filter cdp`.

It provides HTTP API operations (open, list, close tabs) and WebSocket CDP
operations (click, type, eval, wait, text, html, screenshot) for headless browser
automation.

**Served out-of-process — no host CLI subcommand.** The host dispatches the `cdp:`
verb through the provider registry exactly like a built-in (`ResolveVerb("cdp")` →
the out-of-process gRPC provider → `Provider.Invoke` with the full `Op`), and the
plugin drives the running container's CDP endpoint. Authoring is unchanged from a
built-in verb: you write `cdp: open`, never `plugin: cdp`.

### Authoring a `cdp:` step

Each method is the declarative `cdp:` step you author — an ordered list item under
the candy/box `plan:`. The method name is the scalar value for a bare-method step
(`cdp: status`), or the `method:` key of the `cdp:` map when the step carries any
cdp-exclusive field (`tab:`, `expression:`, `url:`, `selector:`, `text:`, `x:`, `y:`,
`artifact:`, `artifact_min_bytes:`, …) — those fields live INSIDE the `cdp:` map. The
shared matchers (`stdout:`, `stderr:`, `exit_status:`) and `context:`/`id:`/`timeout:`
stay siblings of the `cdp:` key. A query is a `check:` step; a navigation/click action
is a `run:` step. All `cdp:` steps are **deploy-context only** (they need a running
container), so author them with `context: [deploy]`. See `/charly-check:check` for the
full method allowlist and YAML shape. Example:

```yaml
- check: the page title is Dashboard
  context: [deploy]
  cdp:
    method: eval
    tab: "1"
    expression: document.title
  stdout: Dashboard
```

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Open URL | `cdp: open` + `url:` | Open URL in new Chrome tab |
| List tabs | `cdp: list` | List all open tabs (id, title, url) |
| Close tab | `cdp: close` + `tab:` | Close a tab by ID |
| Get text | `cdp: text` + `tab:` | Get page text content |
| Get HTML | `cdp: html` + `tab:` | Get page HTML source |
| Get URL | `cdp: url` + `tab:` | Get page title and URL |
| Screenshot | `cdp: screenshot` + `tab:` + `artifact:` | Capture PNG screenshot |
| Click | `cdp: click` + `tab:` + `selector:` | Click element by CSS selector |
| Coords | `cdp: coords` + `tab:` + `selector:` | Show element coords in viewport + desktop |
| Type | `cdp: type` + `tab:` + `selector:` + `text:` | Type into input field |
| Check JS | `cdp: eval` + `tab:` + `expression:` | Evaluate JavaScript |
| Wait | `cdp: wait` + `tab:` + `selector:` | Wait for element |
| Raw CDP | `cdp: raw` + `tab:` | Send raw CDP command |
| Status | `cdp: status` | Check CDP availability, show port and tab count |
| SPA click | `cdp: spa-click` + `tab:` + `x:` + `y:` | Click at canvas coords with SPA scale correction |
| SPA type | `cdp: spa-type` + `tab:` + `text:` | Type text via SPA (bypasses local compositor/Chrome) |
| SPA key | `cdp: spa-key` + `tab:` + `text:` | Send key press via SPA (Return, Escape, F1-F12, etc.) |
| SPA key-combo | `cdp: spa-key-combo` + `tab:` + `text:` | Send modifier combo via SPA (super+e, ctrl+t, alt+F4) |
| SPA mouse | `cdp: spa-mouse` + `tab:` + `x:` + `y:` | Move pointer with SPA scale correction |
| SPA status | `cdp: spa-status` + `tab:` | Show SPA state (canvas, overlay, decoders) |

In the table, each `+ <field>:` entry is a key INSIDE the `cdp:` map
(`cdp: {method: open, url: …}`); only `stdout:`/`stderr:`/`exit_status:` and
`context:`/`id:`/`timeout:` are siblings of the `cdp:` key.

Run a candy's baked `cdp:` steps against a live deployment with
`charly check live <image> --filter cdp`. The `-i <instance>` flag on `charly check
live` selects a multi-instance deployment.

## Architecture

1. Resolves the container name from image + instance (`charly-<image>[-<instance>]`)
2. Discovers the mapped port 9222 via `podman port` / `docker port`
3. **HTTP API** (`/json/list`, `/json/new?url=`, `/json/close/<id>`) for list, open, and close
4. **CDP WebSocket** for interactive operations (click, type, eval, wait, text, html, screenshot, raw)

## Requirements

- A Chrome candy with the `cdp-proxy` supervisord service
- Chrome launched with `--remote-allow-origins='*'` and `--remote-debugging-port=9223` (internal port)
- Container must be running (`charly start`)

The `cdp-proxy` is essential because Chrome 146+ binds DevTools only to 127.0.0.1 and rejects connections with non-localhost Host headers. Chrome binds to `127.0.0.1:9223` internally. The `cdp-proxy` Python script listens on `0.0.0.0:9222` and forwards to Chrome with Host header rewriting. It also rewrites response URLs (`webSocketDebuggerUrl: ws://localhost:9223/...` to `ws://<client-host>:9222/...`) with Content-Length correction, ensuring CDP WebSocket connections work correctly from the host.

## Methods

Each method below is the declarative `cdp:` step you author; queries produce
assertable output (run them as `check:` steps), side-effect actions pass when they
exit 0 (run them as `run:` steps, then follow with a query check to verify the
effect). All steps are deploy-context only.

### Open a URL

```yaml
- run: open example.com in a new tab
  context: [deploy]
  cdp:
    method: open
    url: https://example.com
```

Uses HTTP API: `PUT /json/new?url=<encoded-url>`. Returns the new tab ID (the new
tab is conventionally tab `1` — there is no framework-managed variable to carry a
tab ID between steps; reference subsequent steps as `tab: "1"`).

### List Tabs

```yaml
- check: a tab is open
  context: [deploy]
  cdp: list          # scalar sugar — bare method, no cdp-exclusive fields
  stdout:
    contains: example.com
# Output: one line per tab — "ID  TITLE  URL"
```

Uses HTTP API: `GET /json/list`.

### Close a Tab

```yaml
- run: close the tab
  context: [deploy]
  cdp:
    method: close
    tab: "1"
```

Uses HTTP API: `GET /json/close/<id>`.

### Get Page Content

```yaml
- check: the page text contains the marker
  context: [deploy]
  cdp:
    method: text     # cdp: html → HTML source; cdp: url → title and URL
    tab: "1"
  stdout:
    contains: Example Domain
```

Uses CDP WebSocket: `Runtime.evaluate` with `document.body.innerText` / `document.documentElement.outerHTML`, `Target.getTargetInfo`.

### Screenshot

```yaml
- check: a non-empty screenshot is captured
  context: [deploy]
  cdp:
    method: screenshot
    tab: "1"
    artifact: /tmp/page.png
    artifact_min_bytes: 10000
```

Uses CDP: `Page.captureScreenshot`. Combine with the artifact validators
(`artifact_min_bytes`, `artifact_min_dimensions`, `artifact_not_uniform`) to assert
the capture is real — see `/charly-check:check` "Artifact-validation modifiers".

### Click and Type

```yaml
- run: click the submit button
  context: [deploy]
  cdp:
    method: click
    tab: "1"
    selector: button[type="submit"]
- run: type the email address
  context: [deploy]
  cdp:
    method: type
    tab: "1"
    selector: input[name="email"]
    text: user@example.com
```

Click uses CDP: `Runtime.evaluate` with `deepQuery()` to find element (piercing shadow DOM), `scrollIntoViewIfNeeded()` + `getBoundingClientRect()` for coordinates, `Input.dispatchMouseEvent` for click. Type uses `deepQuery()` + `scrollIntoViewIfNeeded()` + `focus()` to select the element, then `Input.dispatchKeyEvent` for each character (keyDown, char, keyUp — matching Puppeteer behavior).

**Shadow DOM support:** All selector-based methods (click, type, wait) automatically pierce shadow DOM boundaries via recursive `deepQuery()`. This means selectors work on Chrome's internal pages (`chrome://settings/*`), Polymer/Lit web components, and any page using Web Components with shadow DOM. Hidden/zero-sized elements are skipped — only visible matches are returned.

**Note on Chrome internal dialogs:** Some Chrome UI elements (e.g., the "Turn on sync" confirmation dialog) are rendered as native browser chrome, invisible to CDP. Interact with these via the surviving `vnc:` verb keyboard (a `vnc: key` step with `key: Tab` / `key: Return`). VNC screenshots (a `vnc: screenshot` step) show the full desktop including these dialogs, while CDP screenshots only show the page viewport.

### Coordinate Systems

CDP coordinates are **viewport-relative** (relative to Chrome's content area). VNC coordinates are **desktop-absolute** (the full Wayland framebuffer). The offset between them includes Chrome's window position on the desktop plus Chrome's UI chrome (title bar, tab bar, address bar — typically ~107px).

**`cdp: coords`** — Shows an element's coordinates in both systems:

```yaml
- check: the sync button is located
  context: [deploy]
  cdp:
    method: coords
    tab: "1"
    selector: "#sync-button"
# Element:  #sync-button (108x36)
# Viewport: x=1166 y=310  center=(1220, 328)
# Desktop:  x=1166 y=421  center=(1220, 439)  (via window.screenX/screenY, chromeHeight=107)
# Sway:     window at (4, 4) size 1912x1032  (app_id=google-chrome)
```

**Delivering a pointer click via VNC on a `chrome://` page** — CDP mouse events and
JS `.click()` are blocked on `chrome://` pages. Locate the element with `cdp: coords`,
then deliver the click through the surviving `vnc:` verb at the desktop center:

```yaml
- run: click the sync button via VNC pointer
  context: [deploy]
  vnc:
    method: click
    x: 1220
    y: 439
```

**Delivering the same click via the `wl:` verb** — the `wl:` verb (like `vnc:`)
takes desktop-absolute coords directly, so it is the Wayland-native alternative on a
wlroots desktop without VNC. Read the desktop center from the `cdp: coords` step
above, then author a `wl: click` step at those `x:`/`y:`:

```yaml
- run: click the sync button via the wl pointer
  context: [deploy]
  wl:
    method: click
    x: 1220
    y: 439
```

### Evaluate JavaScript

```yaml
- check: read the document title
  context: [deploy]
  cdp:
    method: eval
    tab: "1"
    expression: document.title
  stdout:
    contains: Example
```

Uses CDP: `Runtime.evaluate`. Returns the result value (e.g.
`JSON.stringify(localStorage)` for the full local-storage blob).

### Wait for Element

```yaml
- check: the heading appears
  context: [deploy]
  cdp:
    method: wait
    tab: "1"
    selector: h1
  timeout: 60s        # default 30s — shared #Op modifier, sibling of cdp:
```

Polls with CDP until the CSS selector matches an element.

### Raw CDP Command

```yaml
- run: navigate via a raw CDP method
  context: [deploy]
  cdp:
    method: raw
    tab: "1"
    http_method: Page.navigate           # the raw CDP protocol method
    params: '{"url":"https://example.com"}'   # its JSON params blob
```

Sends an arbitrary CDP method with optional JSON params — `http_method:` names the
CDP protocol method (the input's `method:` is always the verb method `raw`), `params:`
carries the JSON args. Returns the raw CDP response.

## CDP Connection Diagnostics

When a `cdp:` step fails to connect, the plugin's `diagnoseCDP()` routine runs automatically and provides targeted hints:

1. **Chrome process check**: Is Chrome running inside the container? (`pgrep chrome`)
2. **Proxy status**: Is the cdp-proxy forwarding to Chrome? (`supervisorctl status cdp-proxy`)
3. **Port binding**: Is Chrome listening on 127.0.0.1:9223? Is cdp-proxy listening on 0.0.0.0:9222? (`ss -tlnp`)

Hints direct users to relaunch Chrome with a `wl: exec` step running `chrome-wrapper` (the `wl:` verb dispatches out-of-process via `candy/plugin-wl`) — not `charly shell` with bare `swaymsg`, which may lack the correct `SWAYSOCK` path.

## browser-open Script and BROWSER Env

Images with Chrome include a `browser-open` script and set `BROWSER=browser-open` in the environment. When CLI tools inside the container call `xdg-open` or use the `$BROWSER` variable to open a URL, it routes through CDP to open the URL in the running Chrome instance.

## OAuth Automation Example

Complete flow for deploying openclaw with Codex OAuth. **All browser interactions must be VNC-visible** — deliver pointer clicks on the OAuth pages through the `vnc:` verb.

**Critical:** The `openclaw models auth login` TUI requires a real terminal. Do not pipe or redirect it. Use the typed persistent terminal provider (see `/charly-automation:tmux`).

The cdp/vnc interactions are authored as ordered plan steps and run with
`charly check live <image> --filter cdp --filter vnc`; the surrounding host
orchestration (`charly agent terminal`, `charly service`, `charly shell`) is a separate surface,
unaffected by the verb externalization:

```bash
IMG=sway-browser-vnc   # any image composing chrome-cdp + a Wayland desktop + VNC
RUN=0198f140-6b7a-7b90-8a10-aabbccddee02
TARGET='{"deployment":"sway-browser-vnc"}'
PROFILE='{"name":"openclaw-oauth","entrypoint":["openclaw","models","auth","login","--provider","openai-codex","--set-default"],"cols":120,"rows":40,"persistence":"required","transcript":"both"}'

# 1. Prerequisites: Chrome signed into Google with sync enabled
#    See /charly-automation:openclaw-deploy for full Chrome sign-in procedure

# 2. Start OAuth in a typed persistent terminal (real PTY)
charly agent terminal launch "$PROFILE" --target "$TARGET" --run-id "$RUN"

# 3. Read the structured screen/transcript, then drive the browser via the cdp:/vnc: steps below
charly agent terminal snapshot "$PROFILE" --target "$TARGET" --run-id "$RUN"
charly agent terminal transcript "$RUN"
```

```yaml
# candy/<name>/charly.yml — the browser leg as ordered cdp:/vnc: plan steps
plan:
    - run: open the OAuth URL captured from the TUI
      context: [deploy]
      cdp:
        method: open
        url: "${ENV_OAUTH_URL}"      # threaded in via the deploy env
    - run: click "Continue with Google" (VNC-visible)
      context: [deploy]
      cdp:                            # locate, then deliver the pointer via vnc:
        method: coords
        tab: "1"
        selector: button._buttonStyleFix_wvuha_65
    - run: click "Continue" on the Codex consent page (VNC-visible)
      context: [deploy]
      cdp:
        method: coords
        tab: "1"
        selector: button._primary_3rdp0_107
```

```bash
# 6. Verify token exchange completed from typed evidence
charly agent terminal snapshot "$PROFILE" --target "$TARGET" --run-id "$RUN"
# Expected: "OpenAI OAuth complete", "Default model set to openai-codex/gpt-5.4"

# 7. Restart gateway
charly service restart $IMG openclaw
charly shell $IMG -c "openclaw models status"
```

**Tested selectors** (OpenAI auth page):
- "Continue with Google": `button._buttonStyleFix_wvuha_65` (first matching social button)
- "Continue" (consent): `button._primary_3rdp0_107` (black primary button)
- These are CSS class selectors specific to OpenAI's auth UI — may change over time

Key enablers:
- `charly agent terminal launch` provides a real persistent terminal for the TUI (see `/charly-automation:tmux`)
- the `cdp:` verb finds elements by CSS selector; the `vnc:` verb delivers the pointer click (visible to user)
- `cdp-proxy` makes Chrome DevTools accessible from host through podman bridge networking (with Host header rewriting)
- `shm_size: 1g` prevents Chrome from crashing due to /dev/shm exhaustion
- Callback at `localhost:1455` is container-internal (no port mapping needed)

**Stale port 1455:** If a previous OAuth attempt left port 1455 occupied, kill the stale holder: `charly shell $IMG -c 'kill -9 $(ss -tlnp sport = :1455 | grep -oP "pid=\K\d+")'`. If the surviving owner is a live agent run, treat it as an incident instead (per R1): preserve its evidence, complete RCA, and apply an explicit recovery decision.

Source: `candy/plugin-cdp`.

## Google Sign-In Automation

Sign into a Google account inside a running container. Requires `GMAIL_USER` and `GMAIL_PASSWORD` environment variables (set in `.env` or passed via `-e`).

**App Passwords required:** Google accounts with 2FA (now mandatory for most accounts) require a 16-character [App Password](https://myaccount.google.com/apppasswords). App Passwords bypass all verification challenges and 2FA prompts — use them by default for automated sign-in.

**Fresh profile prerequisite:** A fresh `chrome-data` volume triggers Chrome's first-run flow. Use `charly remove <image> --purge` before `charly config` to ensure a clean start. Just rebuilding the image does not reset named volumes.

The sign-in flow is authored as ordered `cdp:`/`vnc:`/`wl:` steps and run with
`charly check live <image> --filter cdp --filter vnc --filter wl`. `chrome://` pages
block CDP mouse events, so the pointer is delivered through the surviving `vnc:`/`wl:`
verbs; text is entered with the `vnc:` verb's real keysym events.

### Step 0: Dismiss Chrome First-Run Dialog

On a fresh profile, Chrome opens a first-run dialog ("Make Google Chrome the default browser") as a **separate window** that CDP cannot see (no debuggable tabs). It tiles alongside any CDP-opened tabs in sway, breaking coordinate translation. Focus and dismiss it with `wl:` steps (sway IPC + a key press):

```yaml
- run: focus the first-run dialog (typically the left window)
  context: [deploy]
  wl:
    method: sway-msg
    command: focus left      # sway-msg's argv rides wl's `command:` field
- run: press OK to dismiss the dialog
  context: [deploy]
  wl:
    method: key
    key: Return
```

After dismissal, Chrome shows `chrome://intro/` — "Sign in to Chrome" with shadow DOM buttons.

### Step 1: Click "Sign in" on chrome://intro

`chrome://` pages block CDP mouse events and JS `.click()`. Locate the button with
`cdp: coords` (shadow DOM path: `intro-app` > `sign-in-promo` > `#acceptSignInButton`),
then deliver the click via the `vnc:` verb at the reported desktop center:

```yaml
- check: the sign-in button is located
  context: [deploy]
  cdp:
    method: coords
    tab: "1"
    selector: "#acceptSignInButton"
```

This opens a new tab with the Google sign-in page (conventionally tab `1`). The tab
ID survives Google's same-tab navigations (email → password → result).

### Step 2: Enter Email (locate via CDP, deliver via VNC)

```yaml
- check: the email field appears
  context: [deploy]
  cdp:
    method: wait
    tab: "1"
    selector: "#identifierId"
  timeout: 30s
- check: the email field is located (focus via vnc: at these coords)
  context: [deploy]
  cdp:
    method: coords
    tab: "1"
    selector: "#identifierId"
```

After focusing the field with `vnc: click` at the reported coords, type with the
`vnc:` verb's real keysym events (a `vnc: type` step with `text: "${ENV_GMAIL_USER}"`). Use
`cdp: coords` to inspect element position in all three coordinate systems (viewport,
desktop via CDP, desktop via sway) for debugging.

### Step 3: Submit Email

Click `#identifierNext` (locate via `cdp: coords`, deliver via `vnc:`), then verify the
transition:

```yaml
- check: the password challenge page is reached
  context: [deploy]
  cdp:
    method: url
    tab: "1"
  stdout:
    contains: challenge/pwd
- check: a verification screenshot is captured
  context: [deploy]
  cdp:
    method: screenshot
    tab: "1"
    artifact: /tmp/step3.png
    artifact_min_bytes: 5000
```

### Step 4: Enter Password

```yaml
- check: the password field appears
  context: [deploy]
  cdp:
    method: wait
    tab: "1"
    selector: input[type="password"]
  timeout: 15s
- check: the password field is located (focus via vnc:, then vnc: type "$GMAIL_PASSWORD")
  context: [deploy]
  cdp:
    method: coords
    tab: "1"
    selector: input[type="password"]
```

### Step 5: Submit Password

Click `#passwordNext` (locate via `cdp: coords`, deliver via `vnc:`), then capture
verification screenshots — `cdp: screenshot` for the viewport and a
`vnc: screenshot` step for the full desktop (catches native dialogs).

### Step 6: Enable Sync (chrome://sync-confirmation)

After successful sign-in, Chrome navigates to `chrome://sync-confirmation/` — a `chrome://` page (NOT a native dialog). CDP can see it but the click must be delivered via `vnc:` (locate via `cdp: coords` on `#confirmButton`, "Yes, I'm in").

Shadow DOM path: `sync-confirmation-app` > `#confirmButton`. Other buttons: `#notNowButton` ("No thanks"), `#settingsButton` ("Settings").

### Handling Challenges

**2FA/CAPTCHA:** Take a VNC screenshot (a `vnc: screenshot` step) and complete manually via a VNC client. App Passwords bypass most challenges.

**Search engine choice:** May appear as a new tab. Probe for it with a `cdp: list` step and select Google via a shadow DOM `cdp: coords` + `vnc:` click if present.

### Sign-In Persistence

Cookies and sync state are stored in the `chrome-data` volume (`~/.chrome-debug`), persisting across container restarts. Use `charly remove <image> --purge` to clear for a fresh start.

### Coordinate Translation for Sign-In

Pointer delivery via the `vnc:`/`wl:` verbs is essential for the sign-in flow:
- **`chrome://` pages** (intro, sync-confirmation): CDP mouse events and JS `.click()` are blocked. `vnc: click` / `wl: click` (locate via `cdp: coords`) is the only way to click.
- **Google sign-in pages**: real pointer events delivered via `vnc:` bypass anti-automation detection.
- **Coordinate math**: viewport center + `window.screenX` + `window.screenY` + `chromeHeight` = desktop coords. On popup windows (no toolbar), `chromeHeight=0`. The `cdp: coords` step already reports the desktop center, so the `vnc: click` / `wl: click` step takes those `x:`/`y:` directly.

Use a `cdp: coords` step to debug coordinate translation. It shows element position in viewport, desktop (via CDP), and desktop (via sway) systems.

## SPA Remote Desktop Interaction (`cdp: spa-*`)

The `cdp: spa-*` methods provide first-class support for interacting with Selkies-style remote desktop SPAs. These bypass the local compositor and Chrome shortcut handlers — the **only way** to send Super+e, Ctrl+T, or Alt+F4 to the remote desktop.

### SPA DOM Structure

- **`input#overlayInput`** (z-index 3, opacity 0, pointer-events: auto) — invisible input overlay capturing all events
- **`canvas#videoCanvas`** (z-index 2, pointer-events: none) — H.264 video render surface
- **Header controls** (fullscreen, gaming mode) — hidden at left=-132px, slide in on mouse hover

### Usage Example

```yaml
- check: the SPA is in a healthy state
  context: [deploy]
  cdp:
    method: spa-status
    tab: "1"
- run: click at canvas coordinates (where elements appear in CDP screenshots)
  context: [deploy]
  cdp:
    method: spa-click
    tab: "1"
    x: 990
    y: 375
- run: type text (bypasses local compositor — no double-char issue)
  context: [deploy]
  cdp:
    method: spa-type
    tab: "1"
    text: hello world
- run: send super+e to open a foot terminal in labwc
  context: [deploy]
  cdp:
    method: spa-key-combo
    tab: "1"
    text: super+e          # also: ctrl+t (new tab in REMOTE Chrome), alt+f4 (close window)
- run: send a special key
  context: [deploy]
  cdp:
    method: spa-key
    tab: "1"
    text: return           # also: escape, F1-F12, etc.
```

See `/charly-check:check` for the precise SPA-method modifier shape.

### Coordinate Scaling

The SPA maps mouse events from canvas to remote desktop with an internal scaling factor; `cdp: spa-click` / `cdp: spa-mouse` apply the correction so a click at canvas position `(x, y)` lands on the right remote-desktop pixel. Determine the scale empirically by comparing the `cdp: spa-click` cursor position (via a `cdp: screenshot`) with the target.

### Keyboard Architecture

`cdp: spa-type` / `cdp: spa-key` / `cdp: spa-key-combo` send `Input.dispatchKeyEvent` directly to the page. The SPA's `onkeydown` handler on `#overlayInput` (with `stopImmediatePropagation`) captures these and forwards to the remote compositor via WebSocket. Only keyDown + keyUp are sent (no "char" event) to prevent double input.

### When to use `spa` vs regular CDP vs VNC/WL

| Scenario | Verb |
|----------|------|
| Click/type in a web page | `cdp: click` / `cdp: type` (CSS selector targeting) |
| Click/type in a remote desktop via SPA | `cdp: spa-click` / `cdp: spa-type` (canvas coordinates) |
| Send Super+key or Ctrl+T to remote desktop | `cdp: spa-key-combo` (only option that works) |
| Click in local compositor | `wl: click` or `vnc: click` |
| Take screenshot of stream content | `cdp: screenshot` (captures canvas) |
| Take screenshot of full client desktop | `vnc: screenshot` or `wl: screenshot` |

## CDP Proxy Verification

Author `cdp: status` → `cdp: open` → `cdp: eval` steps to verify proxy connectivity
on an instance, then run `charly check live <image> -i <instance> --filter cdp`:

```yaml
- check: CDP is available on port 9222
  context: [deploy]
  cdp: status
  stdout:
    equals: ok
- run: open a test page
  context: [deploy]
  cdp:
    method: open
    url: https://ip.me
- check: the proxy IP is reflected by the page
  context: [deploy]
  cdp:
    method: eval
    tab: "1"
    expression: document.querySelector('#ip-lookup').value
  stdout:
    contains: 198.145.102.110
```

This pattern works for any page content extraction via JS — the `cdp: eval` step returns the expression's result directly.

## Cross-References

- `/charly-check:check` -- parent router; the `cdp:` verb catalog entry, the method allowlist, the artifact-validation modifiers, and `charly check live <image> --filter cdp`.
- `/charly-internals:plugin` -- the out-of-process provider model that serves `cdp` (`candy/plugin-cdp`).
- `/charly-check:wl` -- Wayland desktop automation via the declarative `wl:` verb served out-of-process by `candy/plugin-wl` (sibling verb; also the `wl:` sway-* methods for compositor control); takes desktop-absolute coords (use a `cdp: coords` step to translate viewport→desktop).
- `/charly-check:vnc` -- VNC desktop automation via the declarative `vnc:` verb served out-of-process by candy/plugin-vnc (same container, pixel-level interaction); takes desktop-absolute coords (use a `cdp: coords` step to translate viewport→desktop).
- `/charly-check:dbus` -- D-Bus calls and notifications via the declarative `dbus:` verb served out-of-process by `candy/plugin-dbus`.
- `/charly-core:shell` -- Running commands in containers (`--tty` for OAuth flows)
- `/charly-core:charly-config` -- Instance deployment, proxy configuration, removal workflow
- `/charly-image:layer` -- Chrome candy configuration (cdp-proxy service, port declarations)
- `/charly-selkies:selkies-labwc` -- Full SPA DOM structure, coordinate mapping, session resilience
- `/charly-selkies:chrome-devtools-mcp` -- MCP-based browser automation (29 tools via Streamable HTTP)
- `/charly-selkies:chrome` -- Chrome candy with cdp-proxy, env_accept (HTTP_PROXY)

## When to Use This Skill

**MUST be invoked** when the task involves the `cdp:` check verb, Chrome DevTools Protocol, browser automation, clicking elements, taking screenshots, or OAuth flows inside containers. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Desktop automation. Use after a desktop container is running. Preferred over VNC for structured interaction. See also `/charly-check:vnc` (pixel), `/charly-check:wl` (sway subgroup) (window).
