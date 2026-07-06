---
name: sherpa-onnx
description: |
  sherpa-onnx offline text-to-speech.
  Use when working with the sherpa-onnx candy.
---

# sherpa-onnx -- Offline TTS

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (`run:` step) |
| Depends | none |

## Environment

| Variable | Value |
|----------|-------|
| `SHERPA_ONNX_RUNTIME_DIR` | `~/.local/share/sherpa-onnx/runtime` |
| `SHERPA_ONNX_MODEL_DIR` | `~/.local/share/sherpa-onnx/models` |

## Usage

```yaml
# box charly.yml — compose the candy as an inline list in the box body
my-box:
  candy:
    base: fedora
    candy: [sherpa-onnx]
```

## Used In Boxes


## Related Candies
- `/charly-tools:whisper` -- speech-to-text counterpart
- `/charly-tools:sag` -- ElevenLabs TTS alternative

## Related Commands
- `/charly-core:shell` -- run sherpa-onnx CLI inside the container
- `/charly-automation:openclaw-deploy` -- TTS skill registration in OpenClaw

## When to Use This Skill

Use when the user asks about:
- Offline text-to-speech
- sherpa-onnx TTS engine
- ONNX-based speech synthesis
- The `sherpa-onnx` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
