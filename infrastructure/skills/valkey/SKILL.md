---
name: valkey
description: |
  Valkey 9.x key-value store (Redis-compatible) on port 6379 via Remi modular repo.
  Use when working with Valkey, Redis-compatible caching, or the valkey candy.
---

# valkey -- Valkey key-value store

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | none |
| Ports | `6379` |
| Service | `valkey` (supervisord, priority 20) |
| Volume | `valkey-data` -> `~/.valkey` |
| Install files | `charly.yml` only |

## Environment Variables

| Variable | Value |
|----------|-------|
| `VALKEY_URL` | `redis://127.0.0.1:6379` |

## Service Environment (injected into other containers)

| Variable | Template Value | Resolved Example |
|----------|---------------|-----------------|
| `REDIS_URL` | `redis://{{.ContainerName}}:6379` | `redis://charly-valkey:6379` |

Pod-aware: same-container consumers receive `redis://localhost:6379`, cross-container consumers receive `redis://charly-valkey:6379`. When `charly config` runs, `REDIS_URL` is automatically injected into the global `charly.yml` env for service discovery (Redis-compatible protocol).

See `/charly-image:layer` for `env_provide` field docs.

## Packages

- `valkey` (RPM, from Remi modular repo, module `valkey:remi-9.0`)

## Usage

```yaml
# charly.yml
my-app:
  candy:
    - valkey
  ports:
    - "6379:6379"
```

## Related Candies

- `/charly-infrastructure:redis` -- Redis alternative (same port 6379)

## Used In Boxes

- `/charly-distros:valkey-test` (disabled box)

## When to Use This Skill

Use when the user asks about:

- Valkey key-value store
- Redis-compatible caching in containers
- Port 6379 services

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, env_provide, tests block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block
