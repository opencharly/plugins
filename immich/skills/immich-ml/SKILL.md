---
name: immich-ml
description: |
  Immich photo management with CUDA ML backend for face recognition
  and smart search. Includes PostgreSQL, Redis, and the immich-ml service.
  MUST be invoked before building, deploying, configuring, or troubleshooting the immich-ml box.
---

# immich-ml

Immich photo management with GPU-accelerated machine learning for face recognition and smart search.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | agent-forwarding, nodejs, cuda, python-ml, supervisord, postgresql, vectorchord, redis, immich, immich-ml |
| Platforms | linux/amd64 |
| Ports | 2283 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` (quay.io/fedora/fedora:43)
2. `pixi` → `python` → `supervisord` (transitive)
3. `nodejs` — Node.js runtime + pnpm
4. `cuda` — CUDA toolkit, cuDNN
5. `python-ml` — ML Python environment
6. `postgresql` — database on :5432
7. `vectorchord` — VectorChord vector similarity extension
8. `redis` — cache on :6379
9. `immich` — Immich server on :2283
10. `immich-ml` — ML backend on :3003

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 2283 | Immich web UI + API | HTTP |

## Volumes

| Name | Path | Purpose |
|------|------|---------|
| library | ~/.immich/library | Photo/video storage |
| cache | ~/.immich/cache | Thumbnail cache |
| import | ~/.immich/import | Photo import directory |
| external | ~/.immich/external | External library (no-copy) |
| pgdata | ~/.postgresql | PostgreSQL data |
| models | ~/.immich/models | ML models |

## Quick Start

```bash
charly box build immich-ml
charly config setup immich-ml
charly start immich-ml
# Open http://localhost:2283
```

## Key Candies

- `/charly-immich:immich` — Immich server, db init, library/cache volumes
- `/charly-immich:immich-ml` — ML backend for face recognition and smart search
- `/charly-distros:cuda` — GPU support
- `/charly-languages:python-ml` — ML Python environment
- `/charly-infrastructure:postgresql` — database backend
- `/charly-infrastructure:vectorchord` — VectorChord for smart search
- `/charly-infrastructure:redis` — session/cache backend

## Related Boxes

- `/charly-immich:immich` — CPU-only (no ML, no face recognition)
- `/charly-distros:nvidia` — GPU base without Immich
- **CachyOS variant** — `cachyos.immich-ml` is the CachyOS GPU sibling in the
  `opencharly/distro-cachyos` submodule (built on the `cachyos.nvidia` GPU base). See
  `/charly-distros:cachyos`.

## Verification

After `charly start`:
- `charly status immich-ml` — container running
- `charly service status immich-ml` — all services RUNNING
- `curl -s -o /dev/null -w '%{http_code}' http://localhost:2283` — Immich HTTP returns 200
- `curl -s -o /dev/null -w '%{http_code}' http://localhost:3003` — ML backend HTTP returns 200

## Test Coverage

Latest `charly check live immich-ml` run: **61 passed, 0 failed, 2 skipped**.
The 2 skips are `redis-responds` and `redis-port-open` — they reference
`${HOST_PORT:6379}` which isn't mapped on this box (redis is internal
to the pod). Correct skip behavior; no authoring action needed.

Covers postgres binaries + pg_isready, `valkey-compat-redis` package
(Fedora 43 rename — see `/charly-infrastructure:redis`), pytorch + vllm importable
in python-ml pixi env, nodejs + cuda, Immich server `dist/main.js`,
DB migrate script, geodata init SQL, ML venv + `immich_ml/` module.
Deploy-scope: port 2283 host-reachable, `/api/server/ping` returns 200
with `pong`, internal ML endpoint reachable via in-container
`curl http://127.0.0.1:3003/ping`. Box-scope: supervisorctl orchestrates
postgresql + redis + immich-server + immich-ml all RUNNING.

## Related Skills

- `/charly-immich:immich`, `/charly-immich:immich-ml`, `/charly-infrastructure:postgresql`,
  `/charly-infrastructure:vectorchord`, `/charly-infrastructure:redis`, `/charly-distros:nvidia`,
  `/charly-distros:cuda`, `/charly-languages:python-ml`, `/charly-coder:nodejs`,
  `/charly-infrastructure:supervisord`, `/charly-infrastructure:dbus-layer`, `/charly-tools:charly`,
  `/charly-distros:agent-forwarding`
- `/charly-check:check` — framework + runtime variable rules (why skips happen)
- `/charly-core:charly-config` — deploy setup (pg password secret, volume backing)
- `/charly-immich:immich` — non-ML variant

## When to Use This Skill

**MUST be invoked** when the task involves the immich-ml box, Immich ML features, or GPU-accelerated photo management. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
