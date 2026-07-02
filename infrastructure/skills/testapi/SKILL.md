---
name: testapi
description: |
  FastAPI test service on port 9090 routed via testapi.localhost for development testing.
  Use when working with the test API, Traefik routing validation, or service health checks.
---

# testapi -- FastAPI test service

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Ports | 9090 |
| Route | `testapi.localhost:9090` |
| Service | `testapi` (supervisord) |
| Install files | `task:`, `pixi.toml`, `app.py` |

## Usage

```yaml
# charly.yml
fedora-test:
  candy:
    - testapi
```

## Used In Boxes

- `/charly-distros:fedora-test`

## Related Candies

- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-infrastructure:traefik` -- reverse proxy for route handling

## When to Use This Skill

Use when the user asks about:

- Test API service
- Traefik route testing
- `testapi.localhost` endpoint
- Port 9090 service

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
