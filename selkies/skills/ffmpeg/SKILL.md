---
name: ffmpeg
description: |
  FFmpeg multimedia framework (negativo17 nonfree build with H.264/AAC support).
  Use when working with the ffmpeg candy.
---

# ffmpeg -- FFmpeg multimedia

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |
| Repo | negativo17 `fedora-multimedia` |

## Packages

RPM: `ffmpeg` (from negativo17 `fedora-multimedia` repo — full nonfree build with H.264, AAC, etc.)

**Note:** This is NOT `ffmpeg-free` (RPM Fusion). This is the negativo17 build which includes nonfree codecs required for H.264 encoding/decoding.

## Usage

```yaml
# a box composing this candy — the candy list is a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - ffmpeg
```

All candies that need ffmpeg should declare it as a dependency rather than independently adding the negativo17 repo. This ensures a single authoritative install point.

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)
- `hermes` (via `hermes` candy `require: ffmpeg`)
- `hermes-playwright` (via `hermes` candy `require: ffmpeg`)
- `immich` (via `immich` candy `require: ffmpeg`)
- `immich-ml` (via `immich` candy `require: ffmpeg`)
- CUDA-based boxes (via `cuda` candy `require: ffmpeg`)
- Whisper-based boxes (via `whisper` candy `require: ffmpeg`)

## Related Candies
- `/charly-distros:cuda` — Depends on ffmpeg for GPU video processing
- `/charly-tools:whisper` — Depends on ffmpeg for audio transcoding
- `/charly-hermes:hermes` — Depends on ffmpeg for media tooling
- `/charly-immich:immich` — Depends on ffmpeg for photo/video transcoding

## Related Commands
- `/charly-build:build` — Builds the ffmpeg negativo17 RPM into the box
- `/charly-core:shell` — Interactive shell to run `ffmpeg` for media processing

## When to Use This Skill

Use when the user asks about:
- FFmpeg in containers
- Multimedia processing tools
- The `ffmpeg` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, `run:`/`check:` step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
