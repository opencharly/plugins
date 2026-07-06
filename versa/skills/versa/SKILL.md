---
name: versa
description: |
  versa — image bundling marimo reactive notebook environment with Apache Airflow + GPU-accelerated OSM/GTFS analytics + martin vector tiles + 3D terrain via MapLibre + Polars geospatial extensions (polars-st, geopolars) + GeoArrow + deck.gl rendering via lonboard.
  Composes a marimo + airflow + OSM/GTFS analytics stack (agent-forwarding, nvidia, cuda, marimo, airflow, osm-tools, maputnik, notebook-osm, notebook-graph, debug-tools, dbus, charly, plus the versatiles tile-serving layers) on a CachyOS / Arch base into a single pod that exposes 7 host ports and 1 MCP server.
  MUST be invoked before building, deploying, configuring, or troubleshooting the versa image.
---

# versa — marimo + Airflow + OSM/GTFS + martin

GPU-accelerated marimo notebook environment that composes a full
analytics + visualisation stack: marimo notebooks (also acting as MCP
server), Apache Airflow (LocalExecutor + SQLite), OSM data pipeline
(quackosm → tippecanoe → martin), GTFS transit pipeline (gtfs-parquet),
and a MapLibre style editor (maputnik). One MCP server is exposed
(marimo for notebook diagnostics).

The `versa` image name is OUR image identity, deliberately decoupled
from the upstream marimo notebook software the image bundles. The
`candy/marimo/` directory + the `mcp_provide.name: marimo`
MCP-server identity reflect that upstream software identity.

## Image properties

| Property | Value |
|----------|-------|
| Base | `cachyos.cachyos` — owned by the **`opencharly/distro-cachyos`** submodule (`box/cachyos`); main reaches it via the `cachyos` import namespace (the deliberate main → cachyos coupling). CUDA 13 / cuDNN / python-onnxruntime-cpu via CachyOS `extra` repo |
| Platforms | `linux/amd64` only (cuDF + cu130 torch are amd64-only) |
| Layers | 19 (see "Layer stack" below) |
| Ports | 7 (see "Ports + host mappings") |
| MCP servers | 1 (marimo @ container 2718). No airflow MCP wrapper — no Airflow-3 / `/api/v2` release of the upstream package exists; consumers drive Airflow via direct REST `/api/v2/` calls |
| Registry | `ghcr.io/opencharly` |
| Image tag pattern | CalVer (`YYYY.DDD.HHMM`) |
| Builder | `arch.arch-builder` (pixi/npm/cargo/aur) — inherited from versa's bare-local `base: cachyos`. The cachyos base declares the `builder:` map and, because a `builder:` map does NOT cross a namespace boundary, names the qualified `arch.arch-builder` ref (the Arch builder in the `opencharly/distro-arch` submodule, reached via cachyos's `arch` import namespace). versa lives in the same submodule as that base, so it inherits the map directly. See `/charly-distros:cachyos`. |

## Layer stack (composition order)

1. `cachyos` (base — `docker.io/cachyos/cachyos-v3` OCI image, digest-pinned; matches the upstream CachyOS docker repo workflow)
2. `agent-forwarding` — SSH/GPG agent forwarding for in-container git push
3. `nvidia` — driver runtime (`nvidia-utils`, `nvidia-container-toolkit`)
   — an explicit layer entry because the cachyos base doesn't bundle it
4. `cuda` — CUDA toolkit (`cuda` + `cudnn` + `python-onnxruntime-cpu`
   from CachyOS extra repo; `/opt/cuda` symlinked into
   `/usr/{bin,include,lib64}` for path compatibility with the Fedora
   layout). No AUR builds in this image — `build:` is `[pac]` only.
5. `marimo` — `/charly-versa:versa-layer` — pixi env (cudf-polars-cu13,
   torch cu130, geopandas, quackosm, gtfs-parquet, folium, marimo,
   airflow Python deps, plus polars-st / geopolars / geoarrow-pyarrow /
   geoarrow-pandas / lonboard for Polars-native spatial ops + deck.gl
   rendering, plus freestiler for direct DuckDB → PMTiles tile
   generation — gpq-tiles is system-installed via the osm-tools layer
   instead, because its PyPI wheels don't cover Python 3.13/Linux x86_64
   and the pixi env's `no-build = true` blocks sdist resolution),
   supervisord service `marimo edit … --mcp`
6. `airflow` — `/charly-versa:airflow-layer` — 4 supervisord services
   (init/scheduler/dag-processor/webserver). No airflow-mcp wrapper —
   no Airflow-3 v2 release of `mcp-server-apache-airflow` exists;
   consumers drive Airflow via direct REST `/api/v2/` calls.
7. `osm-tools` — `/charly-versa:osm-tools-layer` — tippecanoe (built from
   source), gdal, jq, martin (Rust binary), pmtiles CLI (Go binary),
   gpq-tiles (cargo-installed Rust binary; v0.6.0 from crates.io —
   the system-install fallback for the PyPI-wheel gap)
8. `maputnik` — `/charly-versa:maputnik-layer` — MapLibre style editor
   built with Vite `--base=/`
9. `pmtiles-viewer` — `/charly-versa:pmtiles-viewer` — protomaps/PMTiles
   /app SPA, visual inspector for PMTiles archives (port 8001 → 28001)
10. `shortbread` — `/charly-versa:shortbread` — systemed/tilemaker (C++/Lua)
    + shortbread-tilemaker config — produces shortbread-schema vector
    tiles into `/workspace/tiles/shortbread/`
11. `versatiles-style` — `/charly-versa:versatiles-style` — @versatiles/style
    MapLibre style generator bundled to `/opt/versatiles-style/`
12. `versatiles-fonts` — `/charly-versa:versatiles-fonts` — SDF font glyphs
    (Noto Sans + 9 others) bundled to `/opt/versatiles-fonts/`
13. `maplibre-versatiles-styler` — `/charly-versa:maplibre-versatiles-styler` —
    interactive MapLibre style-switcher control bundled to
    `/opt/maplibre-versatiles-styler/`
14. `versatiles` — `/charly-versa:versatiles` — versatiles-rs CLI binary
    (convert/serve/probe) + `versatiles serve` supervisord service on
    port 8090 → 28090 (parallel tile server to martin)
15. `versatiles-frontend` — `/charly-versa:versatiles-frontend` —
    versatiles-org/versatiles-frontend SPA (port 8002 → 28002); also
    re-exports versatiles-style / fonts / styler at `/style/`,
    `/fonts/`, `/styler/`
16. `notebook-osm` — `/charly-versa:notebook-osm` — data-only layer
    seeding the OSM+GTFS+pipelines notebook into `/workspace/notebooks/`
17. `notebook-graph` — `/charly-versa:notebook-graph` — data-only layer
    seeding `gpu-libraries-demo.py` into `/workspace/notebooks/`;
    exercises cuGraph (nx-cugraph backend), cuML (KMeans), PyG
    (GCNConv on cuda:0 with torch_scatter), and graphistry
18. `debug-tools` — `/charly-versa:debug-tools-layer` — 49 standard
    debug utilities (network/process/file/system/session)
19. `dbus` — D-Bus session bus
20. `charly` — `charly` CLI binary inside the container

## Ports + host mappings

The image declares container ports; the `versa` deploy entry
remaps to host ports for browser reachability:

| Service | Container port | Host port | Path |
|---|---|---|---|
| marimo edit + MCP | 2718 | **22718** | `/` for editor, `/mcp/server` for MCP |
| airflow api-server | 8080 | **28080** | `/api/v2/`, `/auth/token`, `/api/v2/dags/<id>/dagRuns` |
| martin tile server | 3000 | **23000** | `/<source>/{z}/{x}/{y}` (vector tiles), `/<source>` (TileJSON), `/catalog` |
| maputnik static editor | 8000 | **28000** | `/` (SPA root) |
| pmtiles-viewer SPA | 8001 | **28001** | `/` (SPA root — load remote PMTiles archive via the UI's URL input) |
| versatiles-frontend SPA | 8002 | **28002** | `/` (SPA root); `/style/` re-exports versatiles-style bundle |
| versatiles serve | 8090 | **28090** | `/tiles/<source>/{z}/{x}/{y}.pbf` (parallel tile server to martin; serves /workspace/tiles/shortbread/) |

**Host port 8080 is NOT used** for airflow because traefik already
binds it on the operator's machine. Always use **28080** for airflow
from the host.

## Required charly.yml entry

The versa deploy entry is minimal — the seven URL env vars the
notebook reads are all auto-injected via per-producing-layer
`env_provide:` blocks, and the eight container ports are
auto-allocated to free host ports when the operator writes
`port: [auto]`. The user's browser is on the
host; container-internal `localhost:N` URLs do NOT resolve there —
but the auto-derived `*_PUBLIC_URL` vars correctly carry the
host-side mapping, so the browser-bound and kernel-bound URL spaces
stay in sync automatically:

```yaml
versa:
  pod:
    image: versa
    disposable: true
    lifecycle: dev
    port:
      - auto    # auto-allocate one free host port per image-declared
                # container port. The resolved expansion is persisted
                # as `resolved_port:` alongside this entry on the
                # next `charly config versa` / `charly update versa` run.
```

That's the entire entry. No `env:` block — the seven URL env vars
flow from layer `env_provide:`:

| env var | Producer layer | Template |
|---|---|---|
| `MARTIN_PUBLIC_URL` | `osm-tools` | `http://127.0.0.1:{{.HostPort 3000}}` |
| `AIRFLOW_PUBLIC_URL` | `airflow` | `http://127.0.0.1:{{.HostPort 8080}}` |
| `AIRFLOW_API_INTERNAL_URL` | `airflow` | `http://{{.ContainerName}}:8080` (rewritten to `localhost:8080` same-pod) |
| `AIRFLOW_DAGS_DIR` | `airflow` | `/workspace/dags` (static) |
| `VERSATILES_PUBLIC_URL` | `versatiles` | `http://127.0.0.1:{{.HostPort 8090}}` |
| `VERSATILES_STYLE_PUBLIC_URL` | `versatiles-frontend` | `http://127.0.0.1:{{.HostPort 8002}}/style` |
| `VERSATILES_ASSETS_PUBLIC_URL` | `versatiles-frontend` | `http://127.0.0.1:{{.HostPort 8002}}` |

If you need stable host ports across rebuilds (e.g. browser
bookmarks), replace `port: [auto]` with an explicit list — the
`env_provide:` templates substitute against whichever ports you
chose, so the URL env vars stay correct either way:

```yaml
versa:
  pod:
    image: versa
    port:
      - "22718:2718"
      - "28080:8080"
      - "23000:3000"
      - "28000:8000"
      - "28001:8001"
      - "28002:8002"
      - "28090:8090"
```

For cross-pod topologies (airflow in a separate pod on the shared
`charly` podman network), no special handling needed — the
`AIRFLOW_API_INTERNAL_URL` template renders to
`http://<airflow-pod-name>:8080` because `{{.ContainerName}}`
resolves to the airflow image's container, and `podAwareEnvProvides`
only rewrites to `localhost` when consumer and producer share a pod.

**To verify the resolved URLs once the deploy is running**, open the
notebook — the new diagnostic cell at the top (`_resolved_urls`)
renders a polars DataFrame listing every URL env var, its current
value, and whether it came from `env_provide` injection or the
fallback default. See `/charly-versa:notebook-osm` cell #2.

### Multi-instance pattern (Pattern A from /charly-core:deploy)

Run multiple instances of versa side-by-side using the
`<base>/<instance>` deploy-key form. Each instance gets its own
container (`charly-versa`, `charly-versa-ecovoyage`, …), its own workspace
volume, and its own host-port mappings:

```yaml
versa:
  pod:
    image: versa
    disposable: true
    port:
      - auto                   # auto-allocated host ports

versa/ecovoyage:
  pod:
    image: versa               # SAME image, explicit field required
    disposable: true
    volume:
      - name: workspace
        type: bind
        host: /home/user/projects/ecovoyage
    port:
      - "32718:2718"           # explicit pinned ports for stable bookmarks
      - "38080:8080"
      - "33000:3000"
      - "38000:8000"
      - "38001:8001"
      - "38002:8002"
      - "38090:8090"
```

CLI: `charly update versa/ecovoyage` ↔ `charly update versa -i ecovoyage`.

### Pinned-version pattern (Pattern B from /charly-core:deploy)

Run a specific image tag under an arbitrary deploy name (useful for
canaries, regression bisection, or holding back a specific version):

```yaml
versa-pinned-2026.131.2134:
  pod:
    image: ghcr.io/opencharly/versa:2026.131.2134  # exact ref, never re-resolved
    disposable: true
    port:
      - auto
```

Container name: `charly-versa-pinned-2026.131.2134`. CLI:
`charly update versa-pinned-2026.131.2134`. The deploy key has no
relation to the image name; `charly update` always pulls the exact tag
declared in `image:`.

## MCP servers

This image publishes one MCP endpoint (registered by this plugin's
`.mcp.json`):

| Name | Container URL | Tool count | Skill |
|---|---|---:|---|
| marimo | `http://localhost:2718/mcp/server` | 10 (read-only inspection) | `/charly-versa:versa-mcp` |

The marimo MCP server name reflects the upstream software identity,
not OUR image identity. There is no `airflow` MCP — no Airflow-3 /
`/api/v2` release of the upstream `mcp-server-apache-airflow` package
exists, so consumers drive Airflow via direct REST `/api/v2/` calls
instead.

## R10 acceptance

```bash
charly update --build --force-seed versa
charly check live versa         # → 97 passed · 0 failed · 0 skipped
```

The 4 GPU-library probes (cuGraph/cuML/PyG/graphistry) live alongside
the 11 OSM/GTFS probes as `context: [deploy]` steps in the box's
`plan:` in `charly.yml` so they run AFTER every
per-layer plan section:

| probe id | what it checks |
|---|---|
| `versa-notebook-export` | end-to-end `marimo export ipynb` — triggers all 6 self-authored DAGs and renders every cell server-side (the single highest-value probe; 600s timeout) |
| `versa-notebook-size` | rendered `.ipynb` is ≥100 KB (catches empty-cell renders) |
| `versa-martin-monaco` | TileJSON for the canonical `monaco` source returns 200 + body contains `tilejson` + `vector_layers` |
| `versa-martin-monaco-gpqtiles` | same for `monaco-gpqtiles` |
| `versa-martin-monaco-duckdb-mvt` | same for `monaco-duckdb-mvt` |
| `versa-martin-monaco-duckdb-freestiler` | same for `monaco-duckdb-freestiler` |
| `versa-versatiles-shortbread-tile` | versatiles serve returns a non-empty PBF tile for the shortbread output (HEAD content-length probe) |
| `versa-artifact-parquet` | post-DAG `monaco.parquet` ≥500 KB |
| `versa-artifact-pmtiles` | post-DAG `monaco.pmtiles` ≥1 MB |
| `versa-artifact-gtfs` | post-DAG `monaco.gtfs.zip` ≥500 KB |
| `versa-artifact-shortbread` | post-DAG `monaco-shortbread.pmtiles` ≥100 KB |
| `versa-graph-imports` | cugraph + cuml + torch_geometric + torch_scatter + graphistry import + GPU visible |
| `versa-graph-cugraph-pagerank` | `nx.pagerank(G, backend="cugraph")` on karate club; returns 34 rows |
| `versa-graph-notebook-export` | end-to-end `marimo export ipynb` of `gpu-libraries-demo.py` (600s timeout) |
| `versa-graph-notebook-size` | rendered `.ipynb` is ≥10 KB (matches the ~18 KB observed live) |

End-to-end notebook test (executes all 13 cells via marimo's own
export):

```bash
charly cmd versa "/home/user/.pixi/envs/default/bin/marimo \
  export ipynb /workspace/notebooks/osm-monaco-viz.py \
  --include-outputs --sort topological -o /tmp/notebook-run.ipynb -f"
```

Expected outputs (verified end-to-end):

- both DAGs reach `state: success`
- OSM parquet ~824 KB at `/workspace/tiles/work/monaco.parquet`
- pmtiles ~2.6 MB at `/workspace/tiles/pmtiles/monaco.pmtiles`
- GTFS zip ~770 KB at `/workspace/gtfs/raw/monaco.gtfs.zip`
- 98 stops, 15 routes, 5846 trips in `/workspace/gtfs/parquet/`
- streets MapLibre HTML embeds martin URL, mapterhorn DEM, hillshade,
  terrain, sky, TerrainControl
- transit folium HTML embeds 98 `circleMarker` calls
- neither folium map carries the "Make this Notebook Trusted" wrapper

## Deferred GPU libraries

The image installs every GPU library that has a working Linux-cp313
CUDA-13 wheel upstream. The following are skipped because no
compatible wheel exists at build time; re-add them once wheels ship.

- **DGL** — `https://data.dgl.ai/wheels/` has no `cu130/` directory.
  DGL's release matrix typically lags CUDA by 1-2 major versions;
  source-building inside `arch-builder` would cost 20-40 min of
  image-build time and is brittle against CUDA toolkit-layout
  assumptions in DGL's CMake.
- **PyTorch3D** — `https://github.com/facebookresearch/pytorch3d/releases`
  has no cu130 wheel. Source-building would break the pixi
  `no-build = true` invariant load-bearing for the apache-airflow pin.
- **FAISS GPU** — `https://pypi.org/project/faiss-gpu-cu13/` 404s.
  conda-forge ships `faiss-gpu` but pinned to CUDA 11/12, which would
  force a conflicting conda-forge CUDA stack alongside the existing
  PyPI cu130 install. `faiss-cpu` is functional but the user-facing
  decision is "skip rather than CPU fallback".
- **pyg-lib** — only a Windows-cp313 wheel exists at
  `https://data.pyg.org/whl/torch-2.11.0+cu130.html`. PyG falls back
  to pure-Python message-passing without it; the visible API is
  unchanged.
- **torch-spline-conv** — no cp313 wheel at all. Niche convolution
  layer; PyG's other layer types are unaffected.

## Load-bearing transitive: pytest in the pixi env

`pytest` is an explicit `[pypi-dependencies]` entry in
`candy/marimo/pixi.toml` despite no code in this env using pytest as a
test framework. It is an **involuntary runtime dep** of the cupy + torch
2.11 combination:

- cupy ships `testing` as `importlib.util.LazyLoader`
  (`cupy/__init__.py`), and `cupy/testing/__init__.py` eagerly imports
  `cupy.testing._random` which does `import pytest` at module top.
- torch 2.11's `library.custom_op` decorator runs
  `inspect.getmodule(frame) → hasattr(module, "__file__")` during
  fake-op registration, which trips the LazyLoader and forces the
  cupy.testing chain.
- Joint import sequence `import cugraph; import torch_geometric`
  therefore needs `pytest` available in the env, or it
  `ModuleNotFoundError`s deep in torch's fake-op registration.

Upstream cupy packaging defect (a runtime testing helper should not
eagerly `import pytest`); the downstream fix is supplying pytest. Pure-
Python wheel — does not break the `no-build = true` invariant the
`apache-airflow` pin requires.

## Known gotchas

- **User charly.yml needs `image:` field.** `~/.config/charly/charly.yml`
  versa entry must include `image: versa` — otherwise
  `charly update --build` fails with "deploy has no 'image:' field".
- **Marimo session persistence reorders cells.** When a marimo session
  is open and the file changes (e.g. after `--force-seed`), marimo
  re-persists with its session's cell order. Surgical reset:
  `charly service stop versa marimo`, then `charly cmd versa "cp /data/workspace/notebooks/osm-monaco-viz.py /workspace/notebooks/"`, then `charly service start versa marimo`.
- **Martin caches pmtiles mtime at startup.** Re-run a DAG that
  rewrites `monaco.pmtiles` → martin returns 500/204 forever until
  restart. The OSM DAG's `reload_martin` task handles this automatically;
  see `/charly-versa:osm-tools-layer`.
- **Notebook needs `image:` field too.** Already covered above —
  same point worth emphasizing.

## Cross-references

- `/charly-versa:versa-layer` — marimo runtime layer (pixi env, service)
- `/charly-versa:versa-mcp` — marimo MCP server tool catalog
- `/charly-versa:airflow-layer` — Airflow 3.x compat findings
- `/charly-versa:notebook-osm` — the dual-DAG OSM+GTFS notebook
- `/charly-versa:maputnik-layer` — Vite `--base=/` build pattern
- `/charly-versa:osm-tools-layer` — martin reload pattern
- `/charly-versa:debug-tools-layer` — debug toolkit
- `/charly-check:check` — check verbs used by the live probes
- `/charly-core:deploy` — env block authoring + cross-pod topology
- `/charly-internals:disposable` — `disposable: true` semantics
