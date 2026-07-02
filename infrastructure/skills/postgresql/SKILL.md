---
name: postgresql
description: |
  PostgreSQL database server on port 5432 with pgvector extension and persistent data.
  Entrypoint supports POSTGRES_SHARED_PRELOAD_LIBRARIES for extension loading.
  Use when working with PostgreSQL, database configuration, or pgvector.
---

# postgresql -- PostgreSQL database server

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | none |
| Ports | 5432 |
| Volumes | `pgdata` -> `~/.postgresql/data` |
| Service | `postgresql` (supervisord, priority 10) |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `PGDATA` | `~/.postgresql/data` |
| `POSTGRES_HOST_AUTH_METHOD` | `scram-sha-256` |
| `POSTGRES_SHARED_PRELOAD_LIBRARIES` | *(optional)* — comma-separated `.so` names loaded at startup |

The entrypoint also reads these variables (with defaults, not set in charly.yml):
- `POSTGRES_USER` (default: `postgres`) — set by consuming candies (e.g., immich sets `immich`)
- `POSTGRES_DB` (default: `$POSTGRES_USER`) — set by consuming candies
- `POSTGRES_PASSWORD` — required unless `POSTGRES_HOST_AUTH_METHOD=trust`

## Service Environment (injected into other containers)

| Variable | Template Value | Resolved Example |
|----------|---------------|-----------------|
| `PGHOST` | `{{.ContainerName}}` | `charly-postgresql` |
| `PGPORT` | `5432` | `5432` |

Pod-aware: same-container consumers receive `PGHOST=localhost`, cross-container consumers receive `PGHOST=charly-postgresql`. When `charly config` runs, these are automatically injected into the global `charly.yml` env for PostgreSQL service discovery.

See `/charly-image:layer` for `env_provide` field docs.

## Packages

The candy is multi-distro:

- **RPM (Fedora):** `postgresql-server`, `postgresql-contrib`, `pgvector` (vector similarity search extension)
- **PAC (Arch/CachyOS):** `postgresql`, `postgresql-libs` — the Arch `postgresql` package ships the server + contrib tooling; pgvector on Arch is built from the AUR (see `/charly-infrastructure:vectorchord`).

## Usage

```yaml
# charly.yml -- typically used as dependency of immich
my-image:
  candy:
    - postgresql
```

## Used In Boxes

- `/charly-immich:immich`
- `/charly-immich:immich-ml`

## Entrypoint Features

The custom entrypoint (`/usr/local/bin/postgresql-entrypoint.sh`) supports:

- **First-run initialization** — `initdb`, database creation, and `/docker-entrypoint-initdb.d/` scripts
- **Password management** — `POSTGRES_PASSWORD` or `POSTGRES_PASSWORD_FILE`
- **`POSTGRES_SHARED_PRELOAD_LIBRARIES`** — when set, adds `-c shared_preload_libraries=...` to both the init-phase temp server and the final exec. Used by the `vectorchord` candy to load `vchord.so`. Generic mechanism — any extension candy can use it.

## Related Candies

- `/charly-immich:immich` -- primary consumer (depends on postgresql)
- `/charly-infrastructure:vectorchord` -- sets `POSTGRES_SHARED_PRELOAD_LIBRARIES=vchord.so`
- `/charly-infrastructure:redis` -- often paired with postgresql in service stacks

## Related Commands

- `/charly-core:charly-config` — Deploy with secrets provisioning (db-password)
- `/charly-build:secrets` — Manage database credentials

## When to Use This Skill

Use when the user asks about:

- PostgreSQL database setup in containers
- pgvector extension
- Database volume or `PGDATA` configuration
- Port 5432 service
- Database initialization

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
