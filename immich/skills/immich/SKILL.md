---
name: immich
description: |
  Immich photo management server on port 2283. Includes PostgreSQL, Redis,
  and non-free codec support via RPM Fusion. CPU-only (no ML).
  MUST be invoked before building, deploying, configuring, or troubleshooting the immich box.
---

# immich

Self-hosted photo and video management server with full codec support.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora-nonfree |
| Candies | agent-forwarding, nodejs, supervisord, postgresql, vectorchord, redis, immich |
| Platforms | linux/amd64 |
| Ports | 2283 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` → `fedora-nonfree` (RPM Fusion for codecs)
2. `pixi` → `python` → `supervisord` (transitive)
3. `nodejs` — Node.js runtime + pnpm
4. `postgresql` — database on :5432
5. `vectorchord` — VectorChord vector similarity extension
6. `redis` — cache on :6379
7. `immich` — Immich server on :2283, library + cache + import + external volumes

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

## Quick Start

```bash
charly box build immich
charly config immich
charly start immich
# Open http://localhost:2283
```

## Key Candies

- `/charly-immich:immich` — Immich server, db init, library/cache volumes
- `/charly-infrastructure:postgresql` — database backend
- `/charly-infrastructure:vectorchord` — VectorChord for smart search
- `/charly-infrastructure:redis` — session/cache backend
- `/charly-distros:rpmfusion` — non-free codec support (via fedora-nonfree base)

## Related Boxes

- `/charly-distros:fedora-nonfree` — parent base
- `/charly-immich:immich-ml` — adds CUDA ML for face recognition and smart search

## Verification

After `charly start`:
- `charly status immich` — container running
- `charly service status immich` — all services RUNNING
- `curl -s -o /dev/null -w '%{http_code}' http://localhost:2283` — Immich HTTP returns 200

## When to Use This Skill

**MUST be invoked** when the task involves the immich box, photo management, or the CPU-only Immich setup. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
