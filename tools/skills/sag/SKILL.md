---
name: sag
description: |
  ElevenLabs text-to-speech CLI.
  Use when working with the sag candy.
---

# sag -- ElevenLabs TTS CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (`run:` step) |
| Depends | `golang` |

## Packages

RPM: `alsa-lib-devel`

## Environment

| Variable | Value |
|----------|-------|
| `GOPATH` | `~/go` |
| PATH append | `~/go/bin` |

## Usage

```yaml
# box charly.yml — name-first: compose the candy via a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - sag
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:golang` -- build/runtime dependency
- `/charly-tools:sherpa-onnx` -- offline TTS sibling
- `/charly-tools:whisper` -- speech-to-text counterpart

## Related Commands
- `/charly-core:shell` -- run sag CLI inside the container
- `/charly-build:secrets` -- supply ELEVENLABS_API_KEY

## When to Use This Skill

Use when the user asks about:
- ElevenLabs text-to-speech
- TTS in containers
- The `sag` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
