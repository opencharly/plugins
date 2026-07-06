---
name: wf-recorder
description: |
  Wayland screen recorder for wlroots compositors.
  Use when working with the wf-recorder candy.
---

# wf-recorder -- Wayland screen recorder

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

RPM: `wf-recorder`

## What It Does

Native Wayland screen recorder for wlroots-based compositors (sway, labwc, etc.). Captures frames via the `wlr-screencopy` protocol and encodes to MP4/MKV using system ffmpeg. Supports audio capture with `--audio`.

**Note:** Does NOT work on selkies-desktop — use `wl-record-pixelflux` instead (labwc nested in pixelflux can't deliver screencopy frames).

## Usage

```yaml
# a box composing this candy — the candy list is inline
my-box:
  candy:
    base: fedora
    candy: [wf-recorder]
```

## CLI Usage

```bash
# Direct usage (inside container)
wf-recorder -f output.mp4              # Record to MP4
wf-recorder -f output.mp4 --audio      # With audio
wf-recorder -f output.mp4 -r 60        # 60fps
# Stop with Ctrl-C
```

## Integration with the `record:` check verb

Author `record:` plan steps (the declarative verb served out-of-process by
`candy/plugin-record` — no host `charly check` subcommand for it) and run them with
`charly check live sway-browser-vnc --filter record`. A `record: start` step with
`record_mode: desktop` auto-detects wf-recorder; desktop interaction is driven with the
`wl:`/`cdp:` verbs (which keep their host subcommands); `record: stop` + `artifact:`
copies the `.mp4` out:

```yaml
plan:
  - check: a desktop recording starts
    record:
      method: start
      record_name: demo
      record_mode: desktop
    context: [deploy]
  - check: the desktop recording is captured
    record:
      method: stop
      record_name: demo
      artifact: demo.mp4
      artifact_min_bytes: 10000
    context: [deploy]
```

## Included In

- `sway-desktop` metalayer (and all boxes using sway-desktop-vnc)

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)

## Cross-References

- `/charly-check:record` — the `record:` check verb (`record_mode: desktop`) auto-detects wf-recorder
- `/charly-selkies:wl-record-pixelflux` — Alternative for selkies-desktop (pixelflux pipeline)
- `/charly-selkies:wl-screenshot-grim` — Screenshot companion (same wlr-screencopy protocol)
- `/charly-selkies:sway-desktop` — Parent metalayer

## When to Use This Skill

Use when the user asks about:
- Desktop video recording on sway
- wf-recorder in containers
- The `wf-recorder` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, `run:`/`check:` step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
