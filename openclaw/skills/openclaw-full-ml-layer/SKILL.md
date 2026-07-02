---
name: openclaw-full-ml-layer
description: |
  OpenClaw full + ML tools (whisper, sherpa-onnx-tts, CUDA).
  Use when working with the openclaw-full-ml candy.
---

# openclaw-full-ml -- OpenClaw full + ML tools

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (metalayer, layers only) |
| Depends | none (composes other candies) |

## Composed Candies

This metalayer extends `openclaw-full` with ML capabilities:

- `openclaw-full` -- all OpenClaw tools (25 candies)
- `whisper` -- OpenAI Whisper speech-to-text (requires CUDA)
- `sherpa-onnx` -- Offline text-to-speech

## Usage

```yaml
# box charly.yml — composition is a child node, not a top-level list
openclaw-full-ml-box:
    candy:
        base: nvidia
    openclaw-full-ml-box-candy:
        candy:
            - openclaw-full-ml
```

## Used In Boxes


## Related Candies
- `/charly-openclaw:openclaw-full` -- base composition with all OpenClaw tools
- `/charly-tools:whisper` -- speech-to-text component
- `/charly-tools:sherpa-onnx` -- offline TTS component

## Related Commands
- `/charly-automation:openclaw-deploy` -- gateway configuration and channel setup
- `/charly-build:build` -- build boxes composing this metalayer

## When to Use This Skill

Use when the user asks about:
- OpenClaw with ML/AI capabilities
- Speech-to-text and text-to-speech in OpenClaw
- CUDA-accelerated OpenClaw deployment
- The `openclaw-full-ml` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
