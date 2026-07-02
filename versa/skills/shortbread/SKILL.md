---
name: shortbread
description: |
  Shortbread vector-tile schema generation via Tilemaker. The Shortbread schema (https://shortbread-tiles.org) is the de-facto general-purpose OSM vector-tile schema; the layer builds systemed/tilemaker (C++/Lua) from source and bundles the official shortbread-tiles/shortbread-tilemaker Lua + JSON configuration. The notebook's `notebook_osm_shortbread_pipeline` DAG invokes tilemaker on the Monaco PBF to produce `/workspace/tiles/shortbread/monaco-shortbread.pmtiles`, which the versatiles serve service auto-discovers.
  MUST be invoked before building, deploying, or troubleshooting the shortbread layer.
---

# shortbread — Shortbread vector-tile schema generation

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` (transitive; no service of its own) |
| Distros | `arch` + `fedora` (tilemaker is source-built) |
| Build deps | git, make, gcc/gcc-c++, lua/lua-devel, sqlite/sqlite-devel, boost+boost-libs/boost-devel, protobuf/protobuf-devel, shapelib/shapelib-devel, zlib-devel (Fedora only — Arch uses zlib-ng-compat) |
| Output dir | `/workspace/tiles/shortbread/` (versatiles serve watches this) |
| Tools installed | `/usr/local/bin/tilemaker`, `/opt/shortbread-tilemaker/{config.json,process.lua,...}` |

## Why source-built

`systemed/tilemaker` ships no Arch/Fedora package and no GitHub release
binaries. Build from source mirrors the existing tippecanoe pattern in
`/charly-versa:osm-tools-layer`: shallow clone → `make -j$(nproc)` →
`make install PREFIX=/usr/local`. Build duration: ~2-3 minutes on a
warm package cache; binary lands at `/usr/local/bin/tilemaker`.

## Shortbread config bundle

`shortbread-tiles/shortbread-tilemaker` ships:

- `process.lua` — per-feature Lua classifier (decides which OSM tags
  go into which vector-tile layer at which zoom)
- `config.json` — layer/zoom schema definition consumed by tilemaker
  via `--config`
- `get-shapefiles.sh`, `build_test_dataset.sh` — helper scripts (not
  used by the in-pod DAG; bundled for operator reference)

The bundle is cloned to `/opt/shortbread-tilemaker/` at image-build
time with `.git/` removed (image-size reduction).

## DAG invocation

```python
@task
def tilemaker_convert() -> str:
    pbf = "/workspace/tiles/work/monaco.osm.pbf"
    out = "/workspace/tiles/shortbread/monaco-shortbread.pmtiles"
    subprocess.run([
        "tilemaker",
        "--input", pbf,
        "--output", out,
        "--config", "/opt/shortbread-tilemaker/config.json",
        "--process", "/opt/shortbread-tilemaker/process.lua",
    ], check=True)
    return out
```

Tilemaker v3.0+ detects the `.pmtiles` extension on `--output` and
produces a PMTiles archive directly (no `.mbtiles` intermediate).
Monaco-scale runs complete in ~30 seconds.

## Check probes

Build-scope:
- `tilemaker-installed` — `tilemaker --version` exit 0
- `shortbread-process-lua` — `/opt/shortbread-tilemaker/process.lua` exists
- `shortbread-config-json` — `/opt/shortbread-tilemaker/config.json` exists

Deploy-scope:
- `shortbread-tiles-dir-runtime` — `/workspace/tiles/shortbread/` exists

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:versatiles` — the tile-server service that auto-discovers
  `/workspace/tiles/shortbread/*.pmtiles` files
- `/charly-versa:versatiles-style` — MapLibre style generator targeting
  the Shortbread schema (the notebook's shortbread cell renders the
  pipeline output using `colorful()`)
- `/charly-versa:notebook-osm` — DAG cell 2 self-authors the
  `notebook_osm_shortbread_pipeline` that drives this layer
- `/charly-versa:osm-tools-layer` — sibling tippecanoe pipeline + martin
  tile server (parallel infrastructure on port 23000)
