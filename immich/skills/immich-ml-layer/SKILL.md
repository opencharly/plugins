---
name: immich-ml-layer
description: |
  Immich machine learning backend on port 3003 for photo classification and search.
  Use when working with Immich ML features, face detection, or CLIP search.
---

# immich-ml -- Immich machine learning backend

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `immich` |
| Ports | 3003 |
| Volumes | `models` -> `~/.immich/models` |
| Service | `immich-ml` (supervisord, priority 40) |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `IMMICH_MACHINE_LEARNING_ENABLED` | `true` (overrides immich default) |
| `IMMICH_MACHINE_LEARNING_URL` | `http://127.0.0.1:3003` |
| `MACHINE_LEARNING_HOST` | `0.0.0.0` |
| `MACHINE_LEARNING_PORT` | `3003` |
| `MACHINE_LEARNING_WORKERS` | `1` |
| `MACHINE_LEARNING_WORKER_TIMEOUT` | `120` |
| `TRANSFORMERS_CACHE` | `~/.immich/models` |

## Build Setup

- Root-phase tasks download the immich ML module, installs via uv/pip into `/opt/immich/machine-learning/.venv`
- User-phase tasks create `~/.immich/models` (TRANSFORMERS_CACHE) and `~/.cache/immich_ml` (immich ML model cache). The `~/.cache/immich_ml` directory must be created at build time because `~/.cache` may be root-owned from earlier layer builds (npm/pixi). Creating it in tasks: ensures correct UID 1000 ownership.

## Usage

```yaml
# charly.yml -- adds ML to an immich image
immich-ml:
  candy:
    - immich-ml
```

## Used In Boxes

- `/charly-immich:immich-ml`

## Related Candies

- `/charly-immich:immich` -- required base (provides server + database)
- `/charly-distros:cuda` -- GPU acceleration (when used in cuda boxes)

## When to Use This Skill

Use when the user asks about:

- Immich machine learning features
- Face detection or CLIP-based search
- ML model caching or downloads
- Port 3003 configuration
- Enabling ML in Immich

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
