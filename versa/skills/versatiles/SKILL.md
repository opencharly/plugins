---
name: versatiles
description: |
  VersaTiles CLI (versatiles-rs) — a single Rust binary that handles `convert` / `serve` / `probe` / `dev` for the `.versatiles`, `.pmtiles`, `.mbtiles`, and `.tar` tile-container formats. Installed from the pre-built linux-x86_64-gnu tarball on GitHub releases. Ships a supervisord service running `versatiles serve` on port 8090 (host 28090) that watches `/workspace/tiles/shortbread/`, parallel to martin on 3000/23000. The `convert` subcommand is symmetric — PMTiles ↔ .versatiles ↔ MBTiles round-trip — and is exercised end-to-end by both the layer's deploy-scope check probe and a dedicated notebook cell.
  MUST be invoked before building, deploying, or troubleshooting the versatiles layer.
---

# versatiles — VersaTiles CLI + tile server

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Distros | `arch` + `fedora` (binary download) |
| Build deps | curl, jq (for the dynamic release-asset URL resolution) |
| Ports | `8090` (versatiles serve HTTP; host-mapped to **28090**) |
| Service | `versatiles` (supervisord, `restart: always`) |
| Tile dir | `/workspace/tiles/shortbread/` (parallel to martin's `/workspace/tiles/pmtiles/`) |

## Why binary download (not cargo install)

versatiles-rs ships pre-built linux-x86_64-gnu binaries on every
release. `cargo install versatiles` would compile 200+ transitive
crates inside the versa image — wasteful when the upstream CI
already publishes a ready binary. Download pattern mirrors martin's
in `/charly-versa:osm-tools-layer`: GitHub release API → asset URL
matching `versatiles-*linux*x86_64*gnu*.tar.gz` → curl + tar →
`install -m 0755 versatiles /usr/local/bin/`.

## Service spec

```yaml
service:
  - name: versatiles
    exec: /usr/local/bin/versatiles-wrapper.sh
    restart: always
    priority: 37
```

The wrapper:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="/workspace/tiles/shortbread"
mkdir -p "$DIR"
exec /usr/local/bin/versatiles serve --port 8090 "$DIR"
```

Same `mkdir -p` defensive pattern as `martin-wrapper.sh` — first-deploy
state has no PMTiles files yet; versatiles serve starts cleanly on an
empty dir and auto-discovers files as the DAG produces them.

## URL surface

`versatiles serve` exposes:

| URL | Purpose |
|---|---|
| `GET /` | Server root (HTML directory listing) |
| `GET /tiles/<source>/{z}/{x}/{y}.pbf` | Vector tile fetch (the shortbread DAG outputs `monaco-shortbread.pmtiles`, so the source name is `monaco-shortbread`) |
| `GET /tiles/<source>/tilejson.json` | TileJSON metadata |
| `GET /tiles/<source>/style.json` | Default style (if shipped in the container) |

URL format differs from martin's `/<source>/{z}/{x}/{y}` (no `/tiles/`
prefix). The notebook's shortbread cell hardcodes the
`/tiles/monaco-shortbread/{z}/{x}/{y}` pattern in the MapLibre style
override.

## Convert subcommand

`versatiles convert <input> <output>` infers format from extension:

```bash
# PMTiles → .versatiles
versatiles convert monaco.pmtiles monaco.versatiles
# .versatiles → PMTiles (lossless round-trip)
versatiles convert monaco.versatiles monaco-rt.pmtiles
# MBTiles → PMTiles
versatiles convert legacy.mbtiles new.pmtiles
# Directory of PNGs → .versatiles (for raster tilesets)
versatiles convert /tiles-dir/ tiles.versatiles
```

Tile content (MVT-PBF blobs for vector, image bytes for raster) is
copied verbatim — only the container changes. Conversions involving
re-encoding (PNG → WebP, etc.) are also supported via subcommand
flags but not exercised by this image.

The layer's **deploy-scope `versatiles-convert-roundtrip` check
probe** runs the PMTiles → .versatiles → PMTiles round-trip on the
OSM DAG's `monaco.pmtiles` output every time R10 runs, asserting
both intermediate files are readable via `versatiles probe`. The
notebook's dedicated `versatiles convert` demo cell re-runs the
round-trip and renders a `polars.DataFrame` comparing tile counts +
file sizes across all three steps for visual inspection.

## Check probes

Build-scope:
- `versatiles-installed` — `versatiles --version` exit 0
- `versatiles-convert-help` — `versatiles convert --help` exit 0 (verifies the subcommand is linked into the binary)
- `versatiles-wrapper-installed` — `/usr/local/bin/versatiles-wrapper.sh` exists with mode 0755

Deploy-scope:
- `versatiles-running` — supervisord service RUNNING
- `versatiles-port-reachable` — TCP 8090 reachable
- `versatiles-http-up` — `GET /` returns 200
- `versatiles-convert-roundtrip` — end-to-end PMTiles round-trip via
  the OSM DAG output; cleanly SKIPs when `monaco.pmtiles` isn't
  present yet (pre-DAG fresh deploy) so the probe doesn't false-fail
  on first-run state

## CRITICAL: supervisord restart race (same as martin)

Parallel DAGs that call `supervisorctl restart versatiles` race
exactly like the four `reload_martin` calls do. The shortbread DAG's
`reload_versatiles` task uses the same proper synchronization
primitives:

1. `fcntl.flock("/tmp/charly-versatiles-restart.lock")` — serializes the
   supervisorctl invocations globally.
2. TCP readiness probe (bounded 30s) — waits for port 8090 to accept
   connections after restart.
3. HTTP `/` 200 assertion — verifies the END STATE, not the
   supervisorctl exit code (which can be non-zero even when versatiles
   ends up healthy).

See `/charly-versa:osm-tools-layer` "CRITICAL: martin caches pmtiles file
mtime at startup" — same restart-race pattern applies.

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:shortbread` — produces the PMTiles files versatiles serves
- `/charly-versa:versatiles-style` — MapLibre style generator paired with
  versatiles serve as tile backend
- `/charly-versa:versatiles-frontend` — pre-built SPA on port 28002 for
  visually exploring tile content
- `/charly-versa:osm-tools-layer` — sibling martin tile server (port
  23000); the two run in parallel for the comparison surface
- `/charly-versa:notebook-osm` — the versatiles convert round-trip demo
  cell + the shortbread MapLibre cell
