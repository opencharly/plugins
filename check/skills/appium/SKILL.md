---
name: appium
description: |
  MUST be invoked before any work involving: the `appium:` check verb (declarative, dispatched to the out-of-process plugin candy/plugin-appium), Android UI automation, WebDriver session management, APK install via Appium, element find/click/send-keys, mobile-specific WebDriver caps — anywhere the goal is to drive a running Appium 3.x server inside a container via W3C WebDriver from outside.
---

# Appium — W3C WebDriver client

## Overview

`appium:` is a DECLARATIVE check verb that drives a host-side Appium WebDriver
client — authored as `appium: <method>` inside a candy/box plan `check:`/`run:`
step. It is NOT a host CLI command: there is no `charly check appium`. The
verb's implementation and its `github.com/tebeka/selenium` dependency were
dep-shed into the out-of-tree `candy/plugin-appium` plugin module; at check
time the host dispatches `appium:` through the provider registry to that
out-of-process plugin (the same path a bed's checks take via `charly check
live` / `charly check run`).

The plugin talks W3C WebDriver to the container's host-published Appium port
(container `:4723` → host's `HOST_PORT:4723`, e.g. `35001` on the
`check-android-emulator-pod` deploy) at base path `/wd/hub`.

Session lifecycle uses a persistent JSON session file at
`~/.cache/charly/appium/sessions/<image>[_<instance>].json` so multi-step
tests share one WebDriver session across separate `appium:` steps.
`session-create` writes the file; the other operations load it;
`session-delete` removes it and best-effort closes the remote session.

The Appium-specific endpoints not in the standard WebDriver surface
(`install_app`, `is_app_installed`, `remove_app`, etc.) route through
the W3C escape hatch: `POST /session/<id>/execute/sync` with
`{"script": "mobile: installApp", "args": [...]}`.

### Authoring the `appium:` verb in a plan step

The verb is the inline Op of a step — an ordered list item under the candy/box
`plan:` (deploy-context only — `context: [deploy]`); an Appium action that drives the
UI is a `run:` step. The method name is the scalar value for a bare-method step
(`appium: status`), or the `method:` key of the `appium:` map when the step carries
appium-exclusive fields (`caps:`, `apk:`, `strategy:`, `selector:`, `text:`,
`attribute:`, `app_id:`, `activity:`, `keycode:`, `params:`, `expression:`,
`http_method:`, `path:`, `request_body:`, `session:`, `artifact:` and the artifact
validators) — those live INSIDE the `appium:` map. Only the shared matchers
(`stdout:`, `stderr:`, `exit_status:`) and `context:`/`id:`/`timeout:` stay siblings.

```yaml
- check: the Appium server reports ready
  id: appium-up
  appium: status
  stdout: { contains: '"ready":true' }
  context: [deploy]
- run: open a W3C WebDriver session against the emulator
  id: open-session
  appium:
    method: session-create
    caps: |
      {"platformName":"Android","appium:automationName":"UiAutomator2","appium:deviceName":"emulator-5554"}
  context: [deploy]
- run: install the ApiDemos test app
  id: install
  appium:
    method: install-app
    apk: ./tests/data/ApiDemos-debug.apk   # HOST path; staged into the container by the verb
  context: [deploy]
- run: tap the Animation list entry
  id: tap-animation
  appium:
    method: click
    strategy: xpath
    selector: '//android.widget.TextView[@text="Animation"]'
  context: [deploy]
- check: a screenshot of the post-tap screen is captured
  id: snapshot
  appium:
    method: screenshot
    artifact: /tmp/post-tap.png
    artifact_min_bytes: 10000
  context: [deploy]
- run: close the WebDriver session
  id: close
  appium: session-delete
  context: [deploy]
```

## Quick Reference

These are the `appium:` declarative-verb methods (NOT host CLI commands — there
is no `charly check appium`). The method name is the scalar `appium:` value for a
bare-method step; when a step carries modifiers those go INSIDE the `appium:` map
(`appium: {method: click, selector: …}`), and only `stdout:`/`stderr:`/`exit_status:`
and `context:`/`id:`/`timeout:` stay siblings.

| Method | Declarative form | Required map field | Description |
|---|---|---|---|
| `status` | `appium: status` | — | GET /status, prints JSON, fails on HTTP != 200 |
| `session-create` | `appium: {method: session-create, caps: …}` | `caps:` | Create W3C session, persist id |
| `session-delete` | `appium: session-delete` | — | Close session and remove file |
| `install-app` | `appium: {method: install-app, apk: …}` | `apk:` | mobile:installApp escape hatch |
| `find` | `appium: {method: find, selector: …}` (+ `strategy:`) | `selector:` | Find element, prints W3C id |
| `click` | `appium: {method: click, selector: …}` | `selector:` | Find + click |
| `send-keys` | `appium: {method: send-keys, selector: …, text: …}` | `selector:`+`text:` | Find + type |
| `screenshot` | `appium: {method: screenshot, artifact: …}` | `artifact:` | GET /screenshot, decode base64, write PNG |
| `get-text` | `appium: {method: get-text, selector: …}` | `selector:` | find + GET .../text, prints element text |
| `get-attribute` | `appium: {method: get-attribute, selector: …, attribute: …}` | `selector:`+`attribute:` | find + GET .../attribute/<a> (checked/enabled/text/...) |
| `clear` | `appium: {method: clear, selector: …}` | `selector:` | find + POST .../clear |
| `find-all` | `appium: {method: find-all, selector: …}` | `selector:` | POST /elements; prints count + ids |
| `source` | `appium: source` | — | GET /source (UI hierarchy XML) |
| `back` | `appium: back` | — | POST /back (navigate back) |

### Tier 2 — per-class sugar groups (flat `<group>-<op>` method names)

Mirrors `wl`'s `sway-*` / `overlay-*` pattern — the gesture/app/key/device
groups expose flat method names, e.g. `appium: gesture-tap` in a plan step.

| Group | Ops (check-YAML method names) | Key modifiers |
|---|---|---|
| `gesture` | `gesture-tap`, `gesture-double-tap`, `gesture-long-press`, `gesture-drag`, `gesture-swipe`, `gesture-scroll`, `gesture-fling`, `gesture-pinch-open`, `gesture-pinch-close` | `selector`(+`strategy`) **or** `x`+`y`; `direction`+`percent` (swipe/scroll/fling); `params` (JSON: speed/duration/endX/endY/left/top/width/height) |
| `app` | `app-start-activity`, `app-activate`, `app-terminate`, `app-remove`, `app-clear`, `app-is-installed`, `app-state`, `app-current-activity`, `app-current-package` | `app_id` (lifecycle ops); `activity` (`pkg/.activity`, start-activity, intent form) |
| `key` | `key-press`, `key-hide`, `key-shown` | `keycode` (press; 4=BACK, 66=ENTER); `params` (metastate/flags) |
| `device` | `device-info`, `device-battery`, `device-time`, `device-orientation`, `device-set-orientation`, `device-notifications`, `device-get-clipboard`, `device-set-clipboard`, `device-contexts`, `device-context` | `params` (value/name for set-orientation / set-clipboard / context switch) |

### Tier 3 — generic escape hatch (the cdp-`raw` equivalent — 100% coverage)

| Method | Declarative form | Required map field | Description |
|---|---|---|---|
| `execute` | `appium: {method: execute, expression: …}` (+ `request_body:`) | `expression:` | `POST /execute/sync` — any `mobile:` command or JS. Object `request_body` → `[obj]`; array → as-is. Optional `selector:` resolves an element id for `{element}` substitution in `request_body`. |
| `raw` | `appium: {method: raw, http_method: …, path: …}` (+ `request_body:`) | `http_method:`+`path:` | Any W3C call relative to `/session/<id>` (charly prepends it). `http_method:` is the W3C HTTP verb (the input's `method:` is always the verb method `raw`); `path:`/`request_body:` support the `{element}` token when `selector:` is set. Reaches **everything** including `mobile:` via `/execute/sync`. |

**`raw` is the coverage guarantee** — anything not covered by a typed method or
sugar group is reachable here (e.g. `raw GET /element/{element}/rect`,
`raw POST /timeouts {"implicit":10000}`).

`strategy:` accepts: `xpath` (default), `id`, `accessibility-id`,
`class-name`, `android-uiautomator`, `name`, `css`. Mapped to W3C / Appium
locator strings inside the implementation.

## Gotchas

### W3C capabilities (not legacy JSONWire)

Appium 3.x rejects the legacy JSONWire capability format with HTTP 400.
**Always use W3C-style caps** (the `caps:` value lives inside the `appium:` map):

```yaml
appium:
  method: session-create
  caps: |
    {"platformName":"Android",
     "appium:automationName":"UiAutomator2",
     "appium:deviceName":"emulator-5554"}
```

The `appium:` vendor prefix is mandatory on Appium-specific keys
(`automationName`, `deviceName`, `app`, `appPackage`, `appActivity`,
`noReset`, `newCommandTimeout`, …). Plain W3C keys (`platformName`,
`browserName`) have no prefix.

The selenium SDK we use (`github.com/tebeka/selenium`) handles the
`alwaysMatch` wrapping internally — pass flat caps and the SDK wraps.
We unwrap the user's `alwaysMatch` key if present to avoid double-
wrapping.

### `apk:` is a HOST path for BOTH adb and appium

- `adb: install` reads `apk:` from the host filesystem (the host `charly`
  binary pushes via the ADB sync protocol).
- `appium: install-app` ALSO reads `apk:` from the host filesystem. Because
  the in-container Appium server's `mobile: installApp` requires an
  `appPath` it can read (the base64 `{"app": …}` form is rejected with HTTP
  400 "required parameter is missing: appPath"), the verb stages the host
  APK INTO the container via `<engine> cp` to a temp path, calls installApp
  with that in-container path, then removes the temp file. No bind-mount and
  no external staging step are needed — `apk:` is the host path, end to end.

Both install verbs are therefore symmetric: `apk:` is always a host path
(typically `./tests/data/<app>.apk`, resolved against the project root).
If `appium: install-app` fails, check the host path exists, not a container
path.

### `app-start-activity` uses the intent form (verified)

`appium: app-start-activity` with `activity: io.appium.android.apis/.view.X`
sends `mobile: startActivity {"intent":"<activity>"}`. The intent form
(`pkg/.activity`) is what works on this UiAutomator2 build (verified live) —
NOT a split `{appPackage,appActivity}`. Extra intent args go in `params:`.

### Set a W3C implicit wait, or finds race the activity

`app-start-activity` returns before the activity's UI is laid out, so a `find`
fired immediately after it returns "no such element". Set an implicit wait once
after `session-create` so every `find` polls until the element renders:

```yaml
- run: set a W3C implicit wait so every find polls until the element renders
  appium:
    method: raw
    http_method: POST
    path: /timeouts
    request_body: '{"implicit":10000}'
  context: [deploy]
```

(Verified: without it, ~half the per-screen checks fail the layout race; with
it, all pass. The `check-android-emulator-pod` bed does exactly this.)

### `{element}` substitution in execute/raw

`execute` / `raw` resolve an element host-side when `selector:` is set and
substitute its W3C id for the literal token `{element}` in `request_body:`
(execute) and `path:`+`request_body:` (raw), e.g.
`appium: {method: raw, http_method: GET, path: /element/{element}/text, selector: …}`. Single-brace
`{element}` (deliberately NOT `${…}`) so the check runtime-variable resolver
leaves it untouched. `charly box validate` errors if `{element}` appears with no
`selector:`.

### Android-14 permission dialog covers the app

On API 34, ApiDemos (and many apps) raise a runtime POST_NOTIFICATIONS dialog
(`com.google.android.permissioncontroller`) on first launch that covers the
app, so every find returns "no such element". Pre-grant the permission before
driving the app: `adb: {method: shell, arg: [pm, grant, <pkg>, android.permission.POST_NOTIFICATIONS]}`
then `adb: {method: shell, arg: [am, force-stop, <pkg>]}` for a clean launch.

### WebView context switch needs a pinned chromedriver (NOT --allow-insecure)

The API-34 google_apis System WebView is **Chrome 113**. UiAutomator2's
chromedriver autodownload was verified slow/hanging. Instead the `appium-server`
layer pre-bakes chromedriver 113 at `/opt/chromedriver/113` and the WebView
session sets `appium:chromedriverExecutableDir:"/opt/chromedriver/113"` +
`appium:chromedriverDisableBuildCheck:true` (both plain caps, NOT insecure-
gated). `device-contexts` (presence) works with no chromedriver and is the
reliable floor; the `device-context` switch needs the pinned chromedriver.

### Base path `/wd/hub`; AUR-provisioned toolchain

The container's Appium server (`/usr/bin/appium`, from the CachyOS/AUR `appium`
package) listens at base path **`/wd/hub`**. The whole Android toolchain comes
from CachyOS/AUR packages (`appium`, `android-sdk-*`, `android-emulator`,
`android-sdk-build-tools-34` for aapt2) under `/opt/android-sdk`; only the
API-34 system image is sdkmanager-fetched (no package exists).

## Method allowlist + required modifiers

| Method | Required map field | Notes |
|---|---|---|
| `status` | — | Bypasses the SDK — plain `http.Get` against `/status`. |
| `session-create` | `caps:` | Accepts both flat `{"k":"v"}` and pre-wrapped `{"alwaysMatch":{"k":"v"}}`. Use `caps: @path.json` to read from file. Deletes any pre-existing session for the same image+instance first (best-effort), then `selenium.NewRemote` + persist. |
| `session-delete` | — | Best-effort `DELETE /session/<id>` + `rm` of session file. No-op if no session exists. |
| `install-app` | `apk:` | `apk:` is a HOST path. The verb stages it into the container via `<engine> cp`, then `POST /session/<id>/execute/sync` with `mobile: installApp` + `{appPath: <in-container-temp>}`, then removes the temp file. Symmetric with `adb: install`. |
| `find` | `selector:` | `POST /session/<id>/element`, prints the W3C element id (a UUID-ish string). |
| `click` | `selector:` | Find + `POST /session/<id>/element/<eid>/click`. Atomic. |
| `send-keys` | `selector:`+`text:` | Find + `POST /session/<id>/element/<eid>/value` with `{text: <text>}`. |
| `screenshot` | `artifact:` | `GET /session/<id>/screenshot`, base64-decode, write to `artifact:`. Pairs with `artifact_min_bytes:`. |
| `get-text` / `clear` / `find-all` | `selector:` | find-then-act over `/element[s]/<id>/{text,clear}` (find-all → `/elements`). |
| `get-attribute` | `selector:`+`attribute:` | find + `GET .../attribute/<name>`. |
| `source` / `back` | — | `GET /source` / `POST /back`. |
| `gesture-*` | — (element-or-xy enforced); `gesture-swipe`/`scroll`/`fling` need `direction:` | `mobile: <name>Gesture`; element id from `selector:`, else `x:`/`y:`; `percent:`+`params:` merged into args. |
| `app-start-activity` | `activity:` | `mobile: startActivity {intent}`. |
| `app-activate`/`terminate`/`remove`/`clear`/`is-installed`/`state` | `app_id:` | `mobile: <name>App {appId}`. |
| `app-current-activity`/`current-package` | — | `mobile: getCurrent{Activity,Package}`. |
| `key-press` | `keycode:` | `mobile: pressKey {keycode}` (+`params:`). |
| `key-hide`/`key-shown` | — | `mobile: hideKeyboard` / `isKeyboardShown`. |
| `device-info`/`battery`/`time`/`notifications` | — | `mobile: deviceInfo`/`batteryInfo`/`getDeviceTime`/`openNotifications`. |
| `device-orientation`/`contexts` | — | `GET /orientation` / `GET /contexts`. |
| `device-set-orientation`/`set-clipboard` | `params:` | `POST /orientation` / `mobile: setClipboard`. |
| `device-context`/`get-clipboard` | — | `device-context`: empty `params:` → `GET /context`, set → `POST /context {name}`. |
| `execute` | `expression:` | `POST /execute/sync {script,args:[<request_body>]}`; `{element}` from `selector:`. |
| `raw` | `http_method:`+`path:` | arbitrary W3C call under `/session/<id>`; `{element}` from `selector:`. |

## Session-file format + location

`~/.cache/charly/appium/sessions/<image>[_<instance>].json` (XDG-cache; honours
`XDG_CACHE_HOME`):

```json
{
  "session_id": "37e8f3c1-a9b2-4d8e-b6c5-9a4f7c8b1e2d",
  "base_url": "http://127.0.0.1:35001/wd/hub",
  "created_at": "2025-01-15T14:32:17.481Z",
  "image": "check-android-emulator-pod",
  "instance": "",
  "caps": { ... }
}
```

Mode `0600`. Why XDG cache and NOT in-project / NOT `~/.local/share`:

- Session ids are host-local ephemeral state. Different hosts running
  the same image have different containers with different session ids;
  sharing the file (e.g. via Syncthing of an in-project path) would
  corrupt cross-host setups.
- `~/.local/share` is XDG **data** — explicitly Syncthing-replicated on
  this user's hosts. XDG **cache** is the correct location for ephemeral
  host-local state.

Override the session id for a single check with `session:`:

```yaml
- check: capture a screenshot against an explicit session id
  appium:
    method: screenshot
    artifact: /tmp/x.png
    session: 37e8f3c1-...   # bypass the session file
  context: [deploy]
```

## Implementation

The `appium:` verb and its `github.com/tebeka/selenium` dependency live in the
out-of-tree `candy/plugin-appium` plugin module (an external-charly-verb
plugin), NOT in charly's core (which carries no selenium dependency). The verb's
method enum + every appium modifier (including the absorbed `caps:` and the raw
`http_method:`) live in the plugin's OWN input schema
(`candy/plugin-appium/schema/appium.cue`, `#AppiumInput`), served over the Describe
channel and spliced onto the base for validation — so authoring is unchanged
(`appium: status`, not `plugin: appium`); the internal plugin/plugin_input wire
envelope the sugar desugars to is never authored. At
check time the host dispatches it through the provider registry —
`providerRegistry.ResolveVerb("appium")` → the out-of-process `grpcProvider` →
`invokeVerbProvider`, which hands the plugin the full `#Op` as params.

Inside the plugin: `session-create` uses `tebeka/selenium`'s `NewRemote` (which
handles W3C `alwaysMatch` wrapping); all other ops use a small raw-HTTP W3C
client (`w3cSession`) because the SDK can't attach to an existing session id.
The session file is loaded/saved/deleted with XDG path resolution.

The plugin reads the host port from podman's `NetworkSettings.Ports` via
`InspectContainer` — same path as the adb verb.

## Library risks (documented)

`github.com/tebeka/selenium` last released v0.9.9 in 2022. The W3C
WebDriver protocol is stable so it works against Appium 3.x today, but
upstream activity is low. If it goes dormant we'll need to fork or
migrate to a newer library. The blast radius is small — only
`session-create` uses the SDK; the rest go through `w3cSession` (plain
HTTP), so an SDK swap is a single Run() method's worth of code.

`github.com/zach-klippenstein/goadb` (used by the sibling `/charly-check:adb`)
has the same maintenance posture — pinned to a 2020 release. Same
mitigation if it stops working.

## Related skills

- `/charly-check:adb` — sibling verb for low-level Android Debug Bridge
  control (install / shell / screencap / logcat).
- `/charly-check:android` — the `kind: android` device + `apk:` package format +
  `target: android` deploy this UI automation runs against.
- `/charly-check:check` — the unified check system and the Op struct that
  holds every verb discriminator + modifier (one Op per plan step).
- `/charly-tools:android-emulator` (when authored) — the image these verbs target.

## When to Use This Skill

**MUST be invoked** for any task involving the `appium:` declarative check verb
or its plan steps. Invoke this skill BEFORE reading the plugin's Go source or
reaching for `command: curl http://localhost:.../wd/hub/...` workarounds.
