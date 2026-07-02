---
name: whisper
description: |
  OpenAI Whisper local speech-to-text.
  Use when working with the whisper candy.
---

# whisper -- OpenAI Whisper STT

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `pixi.toml` |
| Depends | `python`, `cuda`, `ffmpeg` |

## Usage

```yaml
# box charly.yml — name-first: compose the candy via a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - whisper
```

## Used In Boxes


## Related Candies

- `/charly-languages:python` — Python runtime — required dependency
- `/charly-distros:cuda` — CUDA toolkit — required dependency
- `/charly-selkies:ffmpeg` — FFmpeg multimedia (nonfree codecs) — required dependency
- `/charly-tools:sherpa-onnx` — alternative STT engine (ONNX-based, lighter weight)

## When to Use This Skill

Use when the user asks about:
- Speech-to-text in containers
- OpenAI Whisper setup
- Audio transcription with CUDA
- The `whisper` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
