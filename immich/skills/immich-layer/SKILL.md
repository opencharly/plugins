---
name: immich-layer
description: |
  Immich photo management server on port 2283 with PostgreSQL and Redis.
  Use when working with Immich, photo management, or media library services.
---

# immich -- Self-hosted photo management server

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord`, `nodejs`, `postgresql`, `redis`, `ffmpeg` |
| Ports | 2283 |
| Volumes | `library` -> `~/.immich/library`, `cache` -> `~/.immich/cache`, `import` -> `~/.immich/import`, `external` -> `~/.immich/external` |
| Service | `immich-db-init` (oneshot, priority 15), `immich-server` (priority 30) |
| Route | `immich.localhost:2283` |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `IMMICH_VERSION` | `v2.7.5` |
| `IMMICH_HOST` / `IMMICH_PORT` | `0.0.0.0` / `2283` |
| `IMMICH_MEDIA_LOCATION` | `~/.immich/library` |
| `IMMICH_MACHINE_LEARNING_ENABLED` | `false` |
| `DB_HOSTNAME` / `DB_DATABASE_NAME` | `127.0.0.1` / `immich` |
| `DB_USERNAME` / `DB_PASSWORD` | `immich` / `immich` |
| `REDIS_HOSTNAME` / `REDIS_PORT` | `127.0.0.1` / `6379` |
| `NODE_ENV` | `production` |

## Packages

The candy is multi-distro — image libraries are declared per distro:

- RPM: `vips`, `vips-devel`, `perl-Image-ExifTool`, `libheif`, `LibRaw`, `gcc-c++`, `make`, `unzip`
- PAC: `libvips` (no separate `-devel` split — headers ship in the same package), `libheif`, `libraw`, `perl-image-exiftool`, `gcc` (includes `g++`), `make`, `unzip`

**Note:** FFmpeg is provided via the `ffmpeg` dependency candy rather than installed directly.

## Build Process (tasks:)

The root-phase tasks download Immich source, builds the server, web UI, and core plugin:

1. **Server** — `pnpm install --frozen-lockfile && pnpm --filter immich build && pnpm --filter immich deploy --prod /opt/immich/server`
2. **Geodata** — Downloads reverse geocoding data from geonames.org
3. **Web UI** — `pnpm --filter @immich/sdk --filter immich-web build`
4. **Core Plugin** — Installs `extism-js` (v1.6.0) and `binaryen` (v124), then `pnpm run build` in `plugins/` to compile TypeScript → WASM (`plugin.wasm`). Build tools are cleaned up after compilation.
5. **PostgreSQL extensions** — Init SQL at `/docker-entrypoint-initdb.d/01-immich-extensions.sql` creates `vector`, `vchord CASCADE`, and `earthdistance CASCADE` extensions (runs during first `initdb` only)
6. **Database migration script** — `/usr/local/bin/immich-db-migrate.sh` runs on every container start via the `immich-db-init` supervisord service. Waits for PostgreSQL, then idempotently ensures `vector`, `earthdistance`, and `vchord` (if available) extensions exist. Handles both fresh installs and upgrades of existing databases.
7. **Server startup wrapper** — `/usr/local/bin/immich-server-start.sh` waits for PostgreSQL to be ready before starting the Node.js process. Eliminates the crash-restart loop that previously occurred when supervisord started `immich-server` before PostgreSQL finished recovery.

All pnpm commands use `npm_config_cache=/tmp/npm-root-cache` to avoid creating root-owned files in the container user's `~/.cache` directory.

## Secrets

| Name | Env Vars |
|------|----------|
| `db-password` | `DB_PASSWORD`, `POSTGRES_PASSWORD` |

## Usage

```yaml
# charly.yml
immich:
  candy:
    - immich
```

## Used In Boxes

- `/charly-immich:immich`
- `/charly-immich:immich-ml`

## Related Candies

- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-coder:nodejs` -- Node.js runtime dependency (provides pnpm for the Immich build)
- `/charly-infrastructure:postgresql` -- database dependency
- `/charly-infrastructure:redis` -- cache dependency
- `/charly-selkies:ffmpeg` -- FFmpeg multimedia (nonfree codecs) — required dependency
- `/charly-infrastructure:vectorchord` -- VectorChord extension (migration script creates it if available)
- `/charly-immich:immich-ml` -- optional ML backend

## When to Use This Skill

Use when the user asks about:

- Immich photo management setup
- Photo library configuration
- Immich database or Redis connectivity
- Port 2283 or `immich.localhost` route
- Media processing (vips, ffmpeg, ExifTool)

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
