---
name: osm-tools-layer
description: |
  OpenStreetMap data pipeline tooling: tippecanoe (GeoJSON → MBTiles/PMTiles, built from source), gdal/ogr2ogr, jq, martin (Rust musl static binary on port 3000), pmtiles CLI. Martin reads tiles from /workspace/tiles/pmtiles/.
  Use when working with the osm-tools layer, tippecanoe build steps, the martin tile server config, the martin "Underlying data source was modified" cache issue + DAG-completion supervisord-restart pattern, or the vector-tiles-only output that requires MapLibre GL JS clients (NOT folium TileLayer).
---

# osm-tools — OSM tooling + martin vector-tile server

Bundles every CLI needed to ingest, transform, and serve OSM data
in the versa image. Martin (Rust) is the long-running tile server
at port 3000 (host-mapped to **23000**); everything else is invoked
ad-hoc from DAGs / shell.

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Distros | `arch` + `fedora` (tippecanoe needs gcc-c++/sqlite-devel/zlib-devel on Fedora and gcc/sqlite on Arch for the source build) |
| Ports | `3000` (martin HTTP, host-mapped to **23000**) |
| Service | `martin` (supervisord, `restart: always`) |
| Tile dir | `/workspace/tiles/pmtiles/` |
| Distros packages | gdal, jq, rust + tippecanoe build deps (git, make, gcc-c++/gcc, sqlite-devel/sqlite, zlib-devel where applicable) |

## Tools installed

| Tool | Source | Purpose |
|---|---|---|
| `tippecanoe` | Built from `felt/tippecanoe` source | GeoJSON → MBTiles/PMTiles |
| `ogr2ogr` / `ogrinfo` | Distro pkg `gdal` | Format conversion (e.g. GeoParquet → GeoJSON for tippecanoe) |
| `jq` | Distro pkg `jq` | JSON manipulation (also for inspecting martin's `/catalog`) |
| `martin` | GitHub release musl binary | Rust tile server |
| `pmtiles` | GitHub release tarball (resolved via API) | PMTiles inspection |
| `gpq-tiles` | `cargo install gpq-tiles --root /usr/local` | Direct GeoParquet → PMTiles converter (geoparquet-io/gpq-tiles v0.6.0) |

Tippecanoe is built from source because no Fedora package exists and
upstream ships only source. Build is small (~200 MB clone, <1 min
`make -j`); cleanup keeps the image lean.

gpq-tiles is cargo-installed because its PyPI wheels cover only
Python 3.8 / Linux x86_64 (v0.6.0) — the marimo pixi env is
Python `<3.14` and its `[pypi-options] no-build = true`
(load-bearing for the apache-airflow resolution) blocks sdist
builds. Cargo builds the binary from crates.io directly; the
~/.cargo/registry + .cargo/git caches are dropped after install to
keep the image-size delta tractable (~50 MB for the final binary).

Martin is the **musl** static binary, NOT the gnu build — gnu
hard-depends on `libicuuc.so.74` / `libicui18n.so.74` which Fedora
43 doesn't ship (it has libicu 77). musl is self-contained.

## Service spec

```yaml
service:
  - name: martin
    exec: /usr/local/bin/martin-wrapper.sh
    restart: always
    working_directory: /home/user
```

The wrapper:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="/workspace/tiles/pmtiles"
mkdir -p "$DIR"
exec /usr/local/bin/martin --listen-addresses 0.0.0.0:3000 "$DIR"
```

The `mkdir -p` ensures martin doesn't error/warn when the dir
doesn't exist yet (pre-DAG-run state on a fresh deploy). Martin
auto-discovers tile files in the directory and serves each as a
named source.

## CRITICAL: martin caches pmtiles file mtime at startup

When martin starts, it caches the mtime of every pmtiles file in
its watched directory. If the file is rewritten LATER (e.g. by a
DAG re-run), martin returns:

```
HTTP/1.1 500 Internal Server Error
Underlying data source was modified
```

for some tile fetches and `HTTP 204 No Content` for others. **All
tile fetches break** until martin restarts and re-reads the file.

Martin has NO `--watch` flag (verified via `martin --help`). The
`--cache-expiry` and `--cache-idle-timeout` flags control the tile
cache, not the file-mtime cache.

**Fix in the OSM DAG**: add a `reload_martin` task as the final
DAG step:

```python
@task
def reload_martin(pmtiles_path: str) -> str:
    import subprocess
    subprocess.run(["supervisorctl", "restart", "martin"], check=True)
    return pmtiles_path
```

uid 1000 has supervisorctl access in this image (the `supervisord.sock`
is readable by the container user). The DAG triggers martin restart
after writing each new pmtiles, so martin always serves the freshest
tiles after any DAG run.

## CRITICAL: martin output is VECTOR tiles, not raster

Tippecanoe produces Mapbox Vector Tile (MVT/PBF) format. Martin
serves them with `Content-Type: application/x-protobuf`. **Folium's
`TileLayer` is RASTER-only** — it tries to render the PBF as PNG/JPG,
fails silently → grey map.

The canonical client for vector tiles is **MapLibre GL JS**.
`/charly-versa:notebook-osm` cell 10 uses `mo.iframe` with embedded
MapLibre HTML pointing at martin's TileJSON URL
(`http://localhost:23000/monaco`) as a vector source, with separate
polygon/line/circle layers filtered by `geometry-type`. Three
sibling cells (11-13) render the alternative-engine outputs at
sibling source URLs:

| Source name | Producer DAG | Notebook cell |
|---|---|---|
| `monaco` | `notebook_osm_pipeline` (tippecanoe via duckdb-spatial GeoJSON) | 10 |
| `monaco-gpqtiles` | `notebook_osm_gpqtiles_pipeline` (gpq-tiles direct converter) | 11 |
| `monaco-duckdb-mvt` | `notebook_osm_duckdb_mvt_pipeline` (DuckDB ST_AsMVT + pmtiles.Writer) | 12 |
| `monaco-duckdb-freestiler` | `notebook_osm_duckdb_freestiler_pipeline` (DuckDB → freestiler) | 13 |

`/charly-versa:maputnik-layer` is a visual editor for these styles —
useful for iterating on map appearance without notebook rebuilds.
`/charly-versa:pmtiles-viewer` is a sibling SPA on port 28001 that
inspects any of the four PMTiles archives' bbox / zoom range /
metadata directly in the browser.

## Martin URL surface

Martin auto-discovers files in the watched directory and exposes:

| URL | Purpose |
|---|---|
| `/catalog` | JSON listing of all available sources |
| `/<source>` | TileJSON for a source (use as MapLibre `style.sources[…].url`) |
| `/<source>/{z}/{x}/{y}` | Vector tile fetch for a coord |
| `/health` | Liveness probe |

For monaco.pmtiles → source name `monaco` → tiles at
`/monaco/{z}/{x}/{y}`. Martin reflects the request `Origin` in
`access-control-allow-origin` so cross-port (22718 → 23000) XHR from
marimo works without proxy tricks.

## Check probes

Build-scope:
- `tippecanoe-installed`, `gdal-installed`, `jq-installed`,
  `martin-installed`, `pmtiles-installed` — `--version` exit 0
- `martin-wrapper-installed` — `/usr/local/bin/martin-wrapper.sh`
  exists with mode 0755

Deploy-scope:
- `martin-running` — supervisord program is RUNNING
- `martin-port-reachable` — TCP 3000 reachable
- `martin-http-catalog` — `GET /catalog` returns 200
- `martin-tiles-dir-runtime` — `/workspace/tiles/pmtiles/` exists

The catalog probe passes pre-DAG (with empty source list) and
post-DAG (with the monaco source listed). Tile-content probes are
NOT included — they'd false-fail on cold deploys before any DAG ran.

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:notebook-osm` — DAG that produces pmtiles + MapLibre cell consuming them
- `/charly-versa:maputnik-layer` — visual style editor for the same vector tiles
- `/charly-infrastructure:supervisord` — service runtime
