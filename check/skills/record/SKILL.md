---
name: record
description: |
  Record terminal sessions (asciinema) or desktop video (pixelflux/wf-recorder)
  via the declarative `record:` check verb, served out-of-process by `candy/plugin-record`.
  MUST be invoked before any work involving: the `record:` check verb, terminal recording,
  desktop video recording, or session capture.
---

# Record -- Terminal and Desktop Recording

## Overview

The `record:` check verb manages recording sessions inside running containers. It is
**NOT a host `charly check` subcommand** — it is a declarative check verb served
out-of-process by its plugin (`candy/plugin-record`), parallel to the
`mcp:`/`adb:`/`appium:` plugin verbs. Author a `record:` step in a candy/box plan and
run it against a live deployment with `charly check live <image> --filter record`. It
supports two modes:

1. **Terminal recording** (asciinema) — Records terminal sessions as `.cast` files
2. **Desktop video recording** — Records full-screen video as MP4 files via pixelflux (selkies-desktop) or wf-recorder (sway-desktop)

All recording sessions are managed via tmux sessions with a `record-` prefix. This provides background execution, output monitoring, and clean start/stop lifecycle.

**Served out-of-process — no host CLI subcommand.** `record` is EXEC-based: the host
dispatches the `record:` verb through the provider registry exactly like a built-in
(`ResolveVerb("record")` → the out-of-process gRPC provider → `Provider.Invoke` with
the full `Op`), and the plugin drives the venue (start/stop the recorder, send
commands, copy the artifact out) over charly's live `DeployExecutor` reverse channel —
there is no pre-resolved endpoint. Authoring is unchanged from a built-in verb: you
write `record: start`, never `plugin: record`.

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Start recording | `record: start` (+ optional `record_name:`/`record_mode:`/`record_fps:`/`record_audio:`) | Start a recording session |
| Stop recording | `record: stop` + `artifact:` (+ optional `record_name:`) | Stop and copy the recording file to the host artifact path |
| List recordings | `record: list` | Show active recording sessions |
| Send command | `record: cmd` + `text:` (+ optional `record_name:`) | Send a command line into the recording terminal |

Every `+ <field>:` entry is a key INSIDE the `record:` map (`record: {method: start, record_name: …}`);
only `stdout:`/`stderr:`/`exit_status:` and `context:`/`id:`/`timeout:` are siblings.

Run a candy's baked `record:` steps against a live deployment with
`charly check live <image> --filter record`.

## Methods

Each method is the declarative `record:` step you author — an ordered list item under
the candy/box `plan:`. The method name is the scalar value for a bare-method step
(`record: list`), or the `method:` key of the `record:` map when the step carries
record-exclusive fields (`record_name:`, `record_mode:`, `record_fps:`,
`record_audio:`, `text:`, `artifact:` and the artifact validators) — those live INSIDE
the `record:` map. Only the shared matchers (`stdout:`, `stderr:`, `exit_status:`) and
`context:`/`id:`/`timeout:` stay siblings. All `record:` steps are **deploy-context
only** (they need a running container), so author them with `context: [deploy]`.

### `record: start` — Start Recording

```yaml
- check: a terminal recording starts
  context: [deploy]
  record:
    method: start
    record_name: demo          # session name (default: default); multiple concurrent recordings supported
    record_mode: terminal      # terminal (asciinema), desktop (video), or empty/auto (auto-detect)
    # record_fps: 30           # frames per second for desktop recording (default 30)
    # record_audio: true       # include PulseAudio audio capture (desktop mode)
```

**Auto-detection order** (when `record_mode:` is empty/auto): pixelflux-record → wf-recorder → asciinema

**Output files** (inside container):
- Terminal: `/tmp/charly-recordings/<name>.cast`
- Desktop: `/tmp/charly-recordings/<name>.mp4`

### `record: stop` — Stop Recording

```yaml
- check: the terminal recording captured real events
  context: [deploy]
  record:
    method: stop
    record_name: demo
    artifact: /tmp/demo.cast    # the recording file is copied from the container to this host path
    artifact_min_bytes: 200
    artifact_min_cast_events: 5
```

- Sends a graceful stop signal (exit for asciinema, SIGINT for video recorders), waits up to 5s for graceful shutdown, then force-kills.
- `artifact:` copies the recording file out of the container to the host path. Combine with the artifact validators (`artifact_min_bytes`, `artifact_min_cast_events` for `.cast`, `artifact_not_uniform` for video frames) to assert the capture is real — see `/charly-check:check` "Artifact-validation modifiers".

### `record: list` — List Active Recordings

```yaml
- check: the recording session is active
  context: [deploy]
  record: list
  stdout:
    contains: demo
```

Emits all active recording sessions with name, mode, and file path.

### `record: cmd` — Send Command to Recording

```yaml
- check: a command is sent into the recording
  context: [deploy]
  record:
    method: cmd
    record_name: demo
    text: echo 'Hello World'
```

Sends a command into the recording plugin's private tmux session. For terminal recordings, the command and its output become part of the `.cast` file. This is the typed `record: cmd` operation, not a general terminal-control surface.

## Recording Tools

| Tool | Layer | Desktop | Protocol |
|------|-------|---------|----------|
| asciinema | `asciinema` (or `dev-tools`) | N/A | Terminal capture |
| pixelflux-record | `wl-record-pixelflux` | selkies-desktop | selkies WebSocket capture bridge → H.264 → ffmpeg |
| wf-recorder | `wf-recorder` | sway-desktop | wlr-screencopy |

## Use Case: Terminal Demo Recording

A demo is an ordered list of `record:` steps under a candy/box `plan:`, run together
by `charly check live <image> --filter record`:

```yaml
# candy/<name>/charly.yml — ordered record: steps drive the whole demo
plan:
    - check: the terminal recording starts
      context: [deploy]
      record:
        method: start
        record_name: demo
        record_mode: terminal
    - check: echo into the recording
      context: [deploy]
      record:
        method: cmd
        record_name: demo
        text: echo 'Hello World'
    - check: ls into the recording
      context: [deploy]
      record:
        method: cmd
        record_name: demo
        text: ls -la
    - check: the recording stops and is captured
      context: [deploy]
      record:
        method: stop
        record_name: demo
        artifact: /tmp/demo.cast
        artifact_min_cast_events: 3
```

```bash
charly check live openclaw --filter record    # runs the ordered record: steps above
asciinema play /tmp/demo.cast                  # play back the copied-out artifact
```

Recording sessions are intentionally controlled through `record:` steps so the
resulting cast and artifact checks remain correlated with the check run.

## Use Case: Desktop Walkthrough Video

Compose `record:` with the `cdp:`/`wl:` verbs so the browser/desktop interaction is
visible in the captured video:

```yaml
- check: a desktop recording starts
  context: [deploy]
  record:
    method: start
    record_name: walkthrough
    record_mode: desktop
    record_audio: true
- check: navigate the browser (visible in the recording)
  context: [deploy]
  cdp:
    method: open
    url: https://github.com
- check: click on the desktop
  context: [deploy]
  wl:
    method: click
    x: 640
    y: 360
- check: the walkthrough video is captured
  context: [deploy]
  record:
    method: stop
    record_name: walkthrough
    artifact: /tmp/walkthrough.mp4
    artifact_min_bytes: 10000
    artifact_not_uniform: true
```

```bash
charly check live selkies-desktop --filter record --filter cdp --filter wl
```

## Prerequisites

- **Terminal recording:** `asciinema` layer (or `dev-tools`)
- **Desktop recording (selkies):** `wl-record-pixelflux` layer (included in `selkies-desktop` metalayer)
- **Desktop recording (sway):** `wf-recorder` layer (included in `sway-desktop` metalayer)
- **All modes:** `tmux` layer must be present (for session management)

## Implementation Notes

- `record` is served out-of-process by `candy/plugin-record`; there is NO host `charly check` subcommand for it. The host dispatches the `record:` verb through the provider registry (`ResolveVerb("record")`) and the EXEC-based plugin drives the venue over the live `DeployExecutor` reverse channel.
- `record: cmd` owns the recording session's input path. The cosmetic desktop notification is not part of the check verdict.

## Cross-References

- `/charly-check:check` — the parent check router (the `record:` verb catalog entry, the artifact-validation modifiers, and `charly check live --filter record`)
- `/charly-internals:plugin` — the out-of-process provider model that serves `record` (the EXEC-based reverse channel)
- `/charly-automation:tmux` — Separate typed terminal provider for operator and agent terminal sessions
- `/charly-coder:asciinema` — Terminal recording layer
- `/charly-selkies:wl-record-pixelflux` — Pixelflux video recording layer
- `/charly-selkies:wf-recorder` — wf-recorder video recording layer
- `/charly-selkies:selkies-desktop-layer` — Desktop metalayer with pixelflux recording
- `/charly-selkies:sway-desktop` — Desktop metalayer with wf-recorder
- `/charly-check:wl` — Desktop automation (used alongside recording)
- `/charly-check:wl-overlay` — Fullscreen overlays (title cards, lower-thirds, fades — compose with recording workflow)
- `/charly-check:cdp` — Chrome automation (used alongside recording)

## When to Use This Skill

**MUST be invoked** when the task involves:

- Recording terminal sessions or desktop video
- the `record:` check verb / `record: start`/`stop`/`list`/`cmd` steps
- Creating demo videos or walkthroughs
- Capturing asciinema sessions
- "How do I record my desktop?"
- "How do I make a demo video?"
