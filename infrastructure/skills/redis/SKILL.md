---
name: redis
description: |
  Redis in-memory data store on port 6379 with periodic persistence.
  Use when working with Redis, caching, or session storage in containers.
---

# redis -- Redis in-memory data store

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | none |
| Ports | 6379 |
| Service | `redis` (supervisord, priority 20) |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `REDIS_URL` | `redis://127.0.0.1:6379` |

## Service Environment (injected into other containers)

| Variable | Template Value | Resolved Example |
|----------|---------------|-----------------|
| `REDIS_URL` | `redis://{{.ContainerName}}:6379` | `redis://charly-redis:6379` |

Pod-aware: same-container consumers receive `redis://localhost:6379`, cross-container consumers receive `redis://charly-redis:6379`. When `charly config` runs, `REDIS_URL` is automatically injected into the global `charly.yml` env for Redis service discovery.

See `/charly-image:layer` for `env_provide` field docs.

## Packages

The candy is multi-distro:

- **RPM (Fedora):** `redis` (dnf request) → installed as
  **`valkey-compat-redis`** on Fedora 43. The old `redis` package was replaced;
  dnf resolves the name via `Provides:`, but `rpm -q redis` returns "not
  installed". Any `package:` test must query the real installed name. See
  `/charly-check:check` Authoring Gotcha #8.
- **PAC (Arch/CachyOS):** `valkey` — the Arch `valkey` package provides the
  Redis server and CLI binaries (`/usr/bin/redis-server`, `/usr/bin/redis-cli`),
  so the same service spec and binary paths work on Arch/CachyOS. A `package:`
  test on Arch queries `valkey`.

## Usage

```yaml
# charly.yml -- typically used as dependency of immich
my-image:
  candy:
    - redis
```

## Used In Boxes

- `/charly-immich:immich`
- `/charly-immich:immich-ml`

## Tests

The candy ships 5 deterministic `check:` steps in its `plan:`,
baked into the `ai.opencharly.description` OCI label
(see `/charly-check:check` for the full schema — this candy is the
**gold-standard pattern** referenced there). Each step is one inline Op,
and a probe is a `check:` step:

- **`context: [build]`** (run under `charly check box`, via `podman run --rm`):
  - `redis-binary` — `/usr/bin/redis-server` exists
  - `redis-cli-binary` — `/usr/bin/redis-cli` exists
  - `redis-package` — `valkey-compat-redis` package installed (real
    installed provider on Fedora 43; see Packages note above)
- **`context: [deploy]`** (run under `charly check live` against a live service; uses
  `${HOST_PORT:6379}` runtime substitution so the steps keep working
  if `charly.yml` remaps the host port — host-side tests always use
  `127.0.0.1:${HOST_PORT:N}`, not `${CONTAINER_IP}`):
  - `redis-responds` — `redis-cli -h 127.0.0.1 -p ${HOST_PORT:6379} ping` returns `PONG`
  - `redis-port-open` — TCP dial `127.0.0.1:${HOST_PORT:6379}` succeeds

**Composed-vs-standalone skip behavior**: when redis is a sub-candy of
a larger box (e.g. `immich-ml`) that doesn't expose port 6379 on the
host, the `context: [deploy]` steps correctly skip with
`unresolved variables: HOST_PORT:6379`. No authoring action needed.

## Related Skills

- `/charly-immich:immich` -- primary consumer (depends on redis)
- `/charly-infrastructure:postgresql` -- often paired with redis in service stacks
- `/charly-check:check` -- declarative testing framework (this candy is the gold-standard pattern)
- `/charly-image:layer` -- candy authoring + `env_provide` field docs
- `/charly-infrastructure:valkey` -- Remi-repo Valkey 9 package (separate candy; different version than Fedora's default valkey-compat-redis)

## When to Use This Skill

Use when the user asks about:

- Redis setup in containers
- Caching or session storage
- Port 6379 service
- `REDIS_URL` configuration
