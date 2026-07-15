---
name: adb
description: |
  MUST be invoked before any work involving: the `adb:` check verb (declarative, dispatched to the out-of-process plugin candy/plugin-adb), Android Debug Bridge interaction, APK install/uninstall, device shell command execution, system property reads, screencap, logcat tailing — anywhere the goal is to drive a running Android emulator from outside the container via the host-published ADB server port.
---

# ADB — Android Debug Bridge

## Overview

`adb:` is a DECLARATIVE check verb — authored as `adb: <method>` inside a
candy/box plan `check:`/`run:` step. It is NOT a host CLI command: there is no
`charly check adb`. The verb's implementation and its goadb ADB-wire dependency
were dep-shed into the out-of-tree `candy/plugin-adb` plugin module; at check
time the host dispatches `adb:` through the provider registry to that
out-of-process plugin (the same path a bed's checks take via `charly check
live` / `charly check run`).

The plugin drives a host-side ADB client: it connects to the running
container's host-published ADB server port (container `:5037` → host's
`HOST_PORT:5037`, e.g. `35002` on the `check-android-emulator-pod` deploy)
using `github.com/zach-klippenstein/goadb` and dispatches operations against
the emulator backing that server.

A host-side protocol client, no container-side helper, working against any
deploy that publishes the adb-server port — pod / vm / host / nested all work
transparently because the connection is plain TCP to `127.0.0.1:<host-port>`
and the portforward / passt / etc. layer handles the rest.

### Authoring the `adb:` verb in a plan step

The verb is one inline Op carried by a step — an ordered list item under the
candy/box `plan:` (a probe is a `check:` step; an adb action that changes device
state is a `run:` step). The method name is the scalar value for a bare-method step
(`adb: devices`), or the `method:` key of the `adb:` map when the step carries
adb-exclusive fields (`arg:`, `apk:`, `property:`, `key:`, `query:`, `amount:`,
`artifact:` and the artifact validators) — those live INSIDE the `adb:` map. Only
the shared matchers (`stdout:`, `stderr:`, `exit_status:`) and `context:`/`id:`/
`timeout:` stay siblings.
**`context: [deploy]` only** — needs a running container with a
host-mapped ADB server port; the validator rejects `context: [build]`
use at `charly box validate` time.

Example — each step is an ordered list item under the candy/box `plan:` (mirror
`candy/android-emulator-layer/charly.yml`):

```yaml
- check: the emulator is attached to the adb server
  id: emulator-is-up
  adb: devices
  context: [deploy]
  stdout:
    - contains: "emulator-5554"
- check: the emulator reports boot completed
  id: boot-done
  adb:
    method: getprop
    property: sys.boot_completed
  context: [deploy]
  stdout:
    - contains: "1"
  timeout: 300s
```

See `/charly-check:check` for the full per-verb schema notes; this skill is the
adb-specific method reference.

## Quick Reference

These are the `adb:` declarative-verb methods (NOT host CLI commands — there is
no `charly check adb`). The method name is the scalar `adb:` value for a bare-method
step; when a step carries modifiers those go INSIDE the `adb:` map (`adb: {method:
shell, arg: […]}`), and only `stdout:`/`stderr:`/`exit_status:` and
`context:`/`id:`/`timeout:` stay siblings.

| Method | Declarative form | Required map field | Description |
|---|---|---|---|
| `devices` | `adb: devices` | — | List devices/emulators with state |
| `shell` | `adb: {method: shell, arg: [...]}` | `arg:` (list) | Run a shell command on the emulator |
| `install` | `adb: {method: install, apk: …}` | `apk:` | Install an APK from the host filesystem |
| `uninstall` | `adb: {method: uninstall, arg: [pkgid]}` | `arg: [pkgid]` | Remove a package by id |
| `getprop` | `adb: {method: getprop, property: …}` | `property:` | Read a system property |
| `screencap` | `adb: {method: screencap, artifact: …}` | `artifact:` | Capture a PNG screenshot to a host file |
| `logcat-tail` | `adb: {method: logcat-tail, …}` (+ `amount:` / `query:`) | — | Dump recent logcat lines (uses `logcat -d`) |
| `wait-for-device` | `adb: wait-for-device` (+ sibling `timeout:`) | — | Block until `sys.boot_completed=1` |
| `wait-ui-settled` | `adb: wait-ui-settled` (+ sibling `timeout:`) | — | Block until the foreground is not an ANR dialog (dismissing via HOME) |
| `current-focus` | `adb: current-focus` | — | Print the foreground window line (`mCurrentFocus`) |
| `keyevent` | `adb: {method: keyevent, key: …}` | `key:` | Send a key event (`input keyevent KEYCODE_…`) |

`serial:` selects a specific device (default `emulator-5554`). For a
`<base>/<instance>` pod deploy the instance is addressed by the enclosing bed
(or the `-i` flag on `charly check live` / `charly check run`).

## Method allowlist + required modifiers

| Method | Required map field | Notes |
|---|---|---|
| `devices` | — | Output is one line per device: `<serial>\t<state>` |
| `shell` | `arg:` | `arg[0]` is the program; `arg[1:]` are positional args. Prefix `--` is auto-added so flags don't leak into the outer Kong invocation. |
| `install` | `apk:` | Pushes the APK via the sync protocol to `/data/local/tmp/`, then `pm install -r`. Best-effort cleanup of the staged file. Asserts `Success` in pm output. |
| `uninstall` | `arg:` | `arg[0]` = package id (e.g. `com.example.android.apis`). Same `arg[0]` convention as `shell` to keep the modifier surface flat. |
| `getprop` | `property:` | Property key like `sys.boot_completed`, `ro.build.version.release`. |
| `screencap` | `artifact:` | Runs `screencap -p \| base64` on the device, decodes host-side, writes to `artifact:`. The `base64` round-trip is mandatory — raw binary stdout gets mangled by goadb's shell stream on some emulator builds. Pairs with `artifact_min_bytes:` for size assertion. |
| `logcat-tail` | — | Uses `logcat -d` (dump-and-exit). `amount:` trims to the last N lines host-side; `query:` is the literal filter spec (e.g. `MyApp:I *:S`). |
| `wait-for-device` | — | Polls `getprop sys.boot_completed` every 2s up to `timeout:` (default 60s). Lighter than the wire-protocol `wait-for-device` because that returns the moment the device ATTACHES (well before sys.boot_completed). |
| `wait-ui-settled` | — | Polls `mCurrentFocus` (`dumpsys window`); while a system "Application Not Responding" dialog holds focus it dismisses it with `KEYCODE_HOME` and keeps polling, up to `timeout:`. Prints `settled` on success. **Set `timeout:` generously** (the android-emulator gate uses 600s) — the shared 30s default is too short for a churning emulator. Pure goadb — no in-container shell. |
| `current-focus` | — | Prints the `mCurrentFocus` window line. Assert the foreground app (`stdout: contains: io.appium.android.apis`) or detect a stuck ANR dialog. |
| `keyevent` | `key:` | `input keyevent <key>` via `key: KEYCODE_HOME` / `KEYCODE_BACK` / a numeric code. Generic input building block; `wait-ui-settled` uses the same call internally to dismiss dialogs. |

## Authoring gotchas

### `apk:` must be a host-side path

The host `charly` binary reads the APK from its own filesystem and pushes
via the sync protocol — `apk:` is a path on the host running `charly`, NOT
a container-internal path. (Compare with `appium: install-app` where
`apk:` is the in-container Appium server's view of the path because
Appium reads the file itself.)

### `arg:` for shell commands; prefix `--` is automatic

Always write shell args as a YAML list inside the `adb:` map:

```yaml
- run: list the apidemos packages
  context: [deploy]
  adb:
    method: shell
    arg: [pm, list, packages, io.appium.android.apis]
```

The `--` prefix is automatic — you don't have to escape `-l` / `-p` /
`-fsS` etc. flags. Don't reach for `command:` here; `command:` is a
different verb.

### `arg: [pkgid]` for uninstall

Mirrors `shell`'s convention to avoid adding a dedicated `package:`
field. The validator enforces `arg:` non-empty at config time.

### Host-side screencap needs `screencap -p | base64`

A raw `screencap -p` produces binary PNG bytes that goadb's shell
stream may mangle. The implementation always pipes through base64 and
decodes host-side. This is invisible to authors — `adb: screencap`
"just works" — but worth knowing when debugging.

### `wait-ui-settled` — UI readiness past `sys.boot_completed`

A freshly-booted `google_apis_playstore` emulator runs minutes of GMS
post-boot churn (Play Store auto-update, Chimera config, Heterodyne sync)
that starves the GMS-coupled system UI (Pixel Launcher via AiAi,
systemui). It ANRs, and the "Application Not Responding" dialog occludes
whatever app is foreground — so a UI probe (appium find, `monkey`)
fired right after `sys.boot_completed` silently fails. `sys.boot_completed`
is necessary-but-not-sufficient readiness; `wait-ui-settled` is the
sufficient half: it polls the focused window and dismisses any ANR dialog
with `KEYCODE_HOME` until the foreground is clean. It is **load-independent**
(the ANR is GMS churn, not host load) and adapts to a load-dilated churn
purely via `timeout:`. Pure Go over goadb — no in-container shell, so it
is immune to the stdin-heredoc hazard that breaks shell-based settle loops
(see `/charly-check:check` "in-container `command:` stdin").

```yaml
# Order matters — wait-for-device (boot) BEFORE wait-ui-settled (UI),
# wait-ui-settled BEFORE any UI-interacting step (appium / monkey).
# An ordered list item under the candy/box plan:
- check: the emulator UI has settled past the ANR churn
  id: emulator-ui-settled
  adb: wait-ui-settled
  context: [deploy]
  timeout: 600s
  stdout:
    - contains: settled
```

`current-focus` and `keyevent` are the building blocks `wait-ui-settled`
composes — usable on their own to assert the foreground app or inject a
key (`adb: keyevent` + `key: KEYCODE_BACK`).

### `query:` is a free-form logcat spec

`query: "MyApp:I *:S"` passes `MyApp:I *:S` to logcat verbatim (each
word becomes one positional arg). Don't quote individual words; the
shell-fields split handles separation.

### Long-running wait

`wait-for-device` blocks up to its `timeout:` (default 60s) — set
`timeout:` on the plan step to at least that value, plus a small margin.
Common pattern:

```yaml
- check: wait for the device to finish booting
  adb: wait-for-device
  timeout: 120s
  context: [deploy]
```

## Implementation

The `adb:` verb and its goadb ADB-wire client live in the out-of-tree
`candy/plugin-adb` plugin module (an external-charly-verb plugin), NOT in
charly's core (which carries no goadb dependency). The verb's method enum + every
adb modifier live in the plugin's OWN input schema
(`candy/plugin-adb/schema/adb.cue`, `#AdbInput`), served over the Describe channel
and spliced onto the base for validation — so authoring is unchanged (`adb: devices`,
not `plugin: adb`); the internal plugin/plugin_input wire envelope the sugar desugars
to is never authored. At check time the host
dispatches it through the provider registry —
`providerRegistry.ResolveVerb("adb")` → the out-of-process `grpcProvider` →
`invokeVerbProvider`, which hands the plugin the full `#Op` as params.

The deploy/status seams (`target: android` install + `charly status`) drive the
SAME plugin out-of-process via `charly/android_plugin.go` (`invokeAdbPlugin` +
`AdbDeviceEnv`), so the device probe, the committed-APK install, and the status
read never drift on adb behaviour.

The plugin reads the host port from podman's `NetworkSettings.Ports` via
`InspectContainer` — same source-of-truth used by the check test runner's
`${HOST_PORT:N}` substitution. Host-networked containers expose the container
port AS the host port.

## Related skills

- `/charly-check:appium` — sibling verb for higher-level UI automation against the
  same emulator (W3C WebDriver).
- `/charly-check:android` — the `kind: android` device + `apk:` package format +
  `target: android` deploy. The `adb: install` / `adb: install-app` verbs are thin
  wrappers over the SAME shared installer (`charly/android_install.go`) the apk
  format drives — so the verb, the format, and the deploy target never drift.
- `/charly-check:check` — the unified check system and the Op (a plan step) that
  holds every verb discriminator + modifier.
- `candy/android-emulator` — the image these verbs target.

## When to Use This Skill

**MUST be invoked** for any task involving the `adb:` declarative check verb or
its plan steps. Invoke this skill BEFORE reading the plugin's Go source or
reaching for `command: adb ...` workarounds.
