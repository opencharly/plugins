---
name: pmtiles-viewer
description: |
  PMTiles Viewer — visual inspector for PMTiles archives. TypeScript SPA from protomaps/PMTiles/app built via npm at image build time, served as a static dist by python -m http.server on port 8001 (host 28001). Pairs with the osm-tools layer's martin tile server to inspect all four sibling PMTiles archives the versa image produces.
  MUST be invoked before building, deploying, or troubleshooting the pmtiles-viewer layer.
---

# pmtiles-viewer — visual PMTiles archive inspector

The PMTiles Viewer is a pure-JS SPA from `protomaps/PMTiles/app/`,
the same code deployed publicly at https://pmtiles.io. Built from
upstream source via npm at image build time, served as a static
dist by Python's stdlib `http.server`. Composed by
`/charly-versa:versa` so operators can inspect any of the four
sibling PMTiles archives the image produces — `monaco.pmtiles` (the
tippecanoe baseline), `monaco-gpqtiles.pmtiles`,
`monaco-duckdb-mvt.pmtiles`, `monaco-duckdb-freestiler.pmtiles` —
without leaving the pod.

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Distros | `arch` + `fedora` (needs node + npm + git for the build) |
| Build deps | nodejs, npm, git |
| Ports | `8001` (host-mapped to **28001**) |
| Service | `pmtiles-viewer` (supervisord, `restart: always`) |
| Static dist | `/opt/pmtiles-viewer/build/` (Vite `dist/` renamed) |

## Service spec

```yaml
pmtiles-viewer:
  candy:
    service:
      - name: pmtiles-viewer
        exec: /usr/bin/python3 -m http.server 8001 --directory /opt/pmtiles-viewer/build
        restart: always
        working_directory: /opt/pmtiles-viewer
        priority: 35
```

Pure stdlib server — no marimo-pixi-env coupling. The system
`python3` from supervisord's own dependency handles the static
serve. Priority 35 is one higher than maputnik's 34, just to keep
the supervisord start order deterministic (cosmetic — both are
HTTP-only static servers, neither depends on the other).

## Vite `--base=/` override (locked in by a `check:` step)

PMTiles app's `package.json` build script runs Vite. Without an
explicit base flag Vite defaults to whatever's configured in
`vite.config.ts`; if that's anything other than `/`, the emitted
HTML bakes a subpath into `<script src>` references and they
404 in the browser when served at root.

The build override — an ordered `plan:` step:

```yaml
plan:
  - run: build the PMTiles app SPA from upstream source with the Vite --base=/ override
    command: |
      git clone --depth 1 https://github.com/protomaps/PMTiles /tmp/PMTiles
      cd /tmp/PMTiles/app
      npm ci --no-audit --no-fund
      npm run build -- --base=/
      cp -r dist /opt/pmtiles-viewer/build
      cd /
      rm -rf /tmp/PMTiles /root/.npm
    run_as: root
```

The `check:` step (deploy context) greps the served HTML for forbidden
subpath prefixes and fails if any are present:

```yaml
plan:
  - check: served HTML uses root-relative asset URLs
    id: pmtiles-viewer-asset-base-not-prefixed
    context: [deploy]
    exit_status: 0
    command:
      command: |
        ! curl -fsS http://localhost:8001/ | grep -qE '"/(pmtiles|app)/'
      in_container: true
```

The step is a `check:` step, so it fails when the forbidden prefix is
present.

## Use case in the versa image

The versa image's OSM analytics pipelines write four sibling
PMTiles archives under `/workspace/tiles/pmtiles/`:

| Archive | Producer | Notebook cell |
|---|---|---|
| `monaco.pmtiles` | `notebook_osm_pipeline` (tippecanoe via duckdb-spatial GeoJSON) | streets MapLibre |
| `monaco-gpqtiles.pmtiles` | `notebook_osm_gpqtiles_pipeline` (gpq-tiles direct converter) | gpq-tiles MapLibre |
| `monaco-duckdb-mvt.pmtiles` | `notebook_osm_duckdb_mvt_pipeline` (DuckDB ST_AsMVT + pmtiles.Writer) | DuckDB-MVT MapLibre |
| `monaco-duckdb-freestiler.pmtiles` | `notebook_osm_duckdb_freestiler_pipeline` (DuckDB → freestiler) | DuckDB-freestiler MapLibre |

martin auto-discovers each one and exposes a sibling source under
`http://localhost:23000/<archive-stem>`. The viewer at
`http://127.0.0.1:28001/` accepts a PMTiles URL via its "Load
remote archive" input — point it at e.g.
`http://127.0.0.1:23000/monaco-gpqtiles` to inspect that archive's
bbox / zoom range / tile contents directly in the browser.

## Plan steps

Build context (`context: [build]`):
- `pmtiles-viewer-build-dir-exists` — `/opt/pmtiles-viewer/build` exists (directory)
- `pmtiles-viewer-index-html` — `/opt/pmtiles-viewer/build/index.html` exists
- `nodejs-installed-pmtiles-viewer` — `node --version` succeeds

Deploy context (`context: [deploy]`):
- `pmtiles-viewer-running` — supervisord service RUNNING
- `pmtiles-viewer-port-reachable` — TCP 8001 reachable
- `pmtiles-viewer-http-up` — `GET /` returns 200
- `pmtiles-viewer-asset-base-not-prefixed` — served HTML has root-relative asset URLs

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:osm-tools-layer` — companion martin tile server (the
  four sibling sources the viewer inspects)
- `/charly-versa:notebook-osm` — DAGs producing the four PMTiles
  archives and the four MapLibre cells consuming them
- `/charly-versa:maputnik-layer` — sibling static-SPA-via-http.server
  layer (style editor vs viewer; complementary)
- `/charly-infrastructure:supervisord` — service runtime
