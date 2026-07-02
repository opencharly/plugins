---
name: vectorchord
description: |
  VectorChord PostgreSQL extension for optimized vector similarity search.
  Use when working with VectorChord, vector indices, or smart search performance.
---

# vectorchord -- VectorChord vector similarity extension for PostgreSQL

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `postgresql` |
| Ports | none |
| Volumes | none |
| Service | none |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `VECTORCHORD_VERSION` | `1.1.1` |
| `POSTGRES_SHARED_PRELOAD_LIBRARIES` | `vchord.so` |

## Packages

- `unzip` (RPM / PAC) -- for extracting VectorChord release archives

The candy is multi-distro (Fedora + Arch/CachyOS). On Arch, pgvector comes from
the AUR (see `/charly-infrastructure:postgresql`).

## Build Process (tasks:)

Downloads VectorChord from GitHub releases (tensorchord/VectorChord) and installs the extension:

1. Detects PostgreSQL major version via `postgres --version`
2. Detects extension directories via `pg_config --pkglibdir` and
   `pg_config --sharedir` — this resolves correctly on both Fedora
   (`/usr/lib64/pgsql`, `/usr/share/pgsql`) and Arch/CachyOS
   (`/usr/lib/postgresql`, `/usr/share/postgresql`)
3. Downloads `postgresql-<PG_MAJOR>-vchord_<VERSION>_<ARCH>-linux-gnu.zip`
4. Extracts `vchord.so` to `pkglibdir` and `.control`/`.sql` files to `sharedir/extension/`

Supports both `x86_64` and `aarch64` architectures. PostgreSQL version is detected dynamically.

## How It Works

VectorChord provides the `vchordrq` index type for PostgreSQL, replacing pgvector's `ivfflat` with an optimized approximate nearest-neighbor search algorithm. Key differences:

- **No result cap** -- pgvector's ivfflat has an inherent limit (~40 results); vchordrq does not
- **`shared_preload_libraries`** -- VectorChord's `.so` must be loaded at PostgreSQL startup via the `POSTGRES_SHARED_PRELOAD_LIBRARIES` env var (consumed by the postgresql candy's entrypoint)
- **Extension creation** -- `CREATE EXTENSION vchord CASCADE;` (handled by the immich candy's migration script)

## Version Requirements (Immich v2.7.2)

- pgvector >= 0.7, < 0.9 (provided by postgresql candy)
- VectorChord >= 0.3, < 2.0 (provided by this candy)
- PostgreSQL >= 14, < 19 (Fedora 43 ships PG 18)

## Usage

```yaml
# charly.yml -- used alongside postgresql for Immich smart search
my-image:
  candy:
    - postgresql
    - vectorchord
    - immich
```

## Used In Boxes

- `/charly-immich:immich`
- `/charly-immich:immich-ml`

## Related Candies

- `/charly-infrastructure:postgresql` -- required dependency (provides PostgreSQL server and pgvector)
- `/charly-immich:immich` -- primary consumer (migration script creates the extension)

## When to Use This Skill

Use when the user asks about:

- VectorChord extension installation or configuration
- Vector similarity search performance
- PostgreSQL shared_preload_libraries configuration
- Immich smart search or face recognition index types
- `vchordrq` index type

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
