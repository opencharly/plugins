---
name: summarize
description: |
  Summarize CLI for extracting text/transcripts from URLs and files.
  Use when working with the summarize candy.
---

# summarize -- URL/transcript extractor CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `package.json` |
| Depends | `nodejs` |

## Usage

```yaml
# box charly.yml — compose the candy as an inline list in the box body
my-box:
  candy:
    base: fedora
    candy: [summarize]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:nodejs` — runtime dependency
- `/charly-openclaw:openclaw-full` — metalayer that bundles summarize
- `/charly-tools:whisper` — speech-to-text companion in the `openclaw-full-ml` candy

## Related Commands
- `/charly-core:shell` — run summarize CLI inside the container
- `/charly-build:build` — rebuild after candy changes

## When to Use This Skill

Use when the user asks about:
- Extracting text or transcripts from URLs
- Content summarization tools
- The `summarize` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
