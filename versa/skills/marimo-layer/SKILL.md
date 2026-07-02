---
name: marimo-layer
description: |
  marimo reactive notebook server (also runs as MCP server via --mcp), GPU-accelerated OSM/GTFS analytics deps (cudf-polars-cu13, polars, geopandas, quackosm, gtfs-parquet), Apache Airflow Python deps (the airflow layer ships no pixi env), and the marimo-team/learn curriculum + marimo-team/skills bundle for you.
  Use when working with the marimo layer, its pixi environment, the supervisord service spec, or the cell-display + mo.iframe rendering patterns.
---

# marimo — reactive notebook + MCP server

The marimo layer composes the entire notebook runtime: a single
pixi env that hosts marimo + airflow + GPU-accelerated polars +
geospatial tooling (the airflow layer is service-only and reaches
into THIS pixi env for its Python). The supervisord service starts
marimo with `--mcp` so the same port (2718) serves both the editor
UI and the MCP server.

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `cuda`, `supervisord` |
| Distros | `fedora` (sole supported — cudf-polars-cu13 is amd64-fedora-only) |
| Ports | `2718` (marimo edit + MCP — host-mapped to `22718`) |
| Service | `marimo` (supervisord, `restart: always`) |
| MCP provides | `marimo` at `http://{{.ContainerName}}:2718/mcp/server` (Streamable HTTP) |
| Install files | `charly.yml`, `pixi.toml`, `marimo-skills.tar.gz` (curriculum bundle) |
| Env (runtime) | `MARIMO_SKILLS_DIR=/opt/marimo-skills`, `NVIDIA_PYTHON_PROJECT=~/.pixi`, `LD_LIBRARY_PATH=/usr/lib64` |

## Pixi env — version-pin rationale

The pixi env is large (~270 packages). Headline pins worth
understanding:

```toml
python = "<3.14"          # build #7 picked 3.14, no Python framework supports it yet
polars = "*"              # constrained by cudf-polars-cu13 to >=1.30,<1.39
cudf-polars-cu13 = "*"    # CUDA-13 RAPIDS 26.4 series, NOT polars[gpu]
torch = { version = "*", index = "https://download.pytorch.org/whl/cu130" }
marimo = "*"
nbformat = "*"            # required by `marimo export ipynb --include-outputs`
apache-airflow = "*"      # the airflow layer reaches into THIS env
mcp-server-apache-airflow = "*"
fastmcp = "*"
quackosm = "*"            # PBF → GeoParquet via DuckDB Spatial
gtfs-parquet = "*"        # GaspardMerten/gtfs-parquet — GTFS zip → polars Parquet
geopandas = "*"           # + shapely, fiona, pyproj
folium = "*"              # Leaflet wrapping
```

**`cudf-polars-cu13` deliberately**: NOT `polars[gpu]`. The `[gpu]`
extra pulls `cudf-polars-cu12`, which would conflict with our cu130
torch wheels. Direct alignment with cu130 — no forward-compat gamble,
no fallback path needed. The trade-off: `polars` resolver-pinned to
`>=1.30,<1.39` per cudf-polars-cu13's own constraint.

**`nbformat` was added** for verification tooling — without it,
`marimo export ipynb --include-outputs` fails with "nbformat is
required to convert marimo notebooks to ipynb" and the per-cell
output capture path is unavailable.

**`gtfs-parquet`** added in commit `623b542` — provides
`parse_gtfs(zip_or_url) → write_parquet(dir)` for the GTFS DAG that
the notebook self-authors at runtime.

## Service spec

```yaml
service:
  - name: marimo
    exec: "%(ENV_HOME)s/.pixi/envs/default/bin/marimo edit --host 0.0.0.0 --port 2718 --no-token --headless --mcp --mcp-allow-remote %(ENV_HOME)s/workspace"
    restart: always
    working_directory: "%(ENV_HOME)s"
```

Flag breakdown:

- `--host 0.0.0.0` — bind all interfaces so the host-port mapping reaches it
- `--port 2718` — base port for both editor UI and MCP
- `--no-token` — dev posture; no editor login
- `--headless` — don't try to open a browser inside the container
- `--mcp` — enable the MCP HTTP server on the same port (`/mcp/server`)
- `--mcp-allow-remote` — **mandatory** with `--host 0.0.0.0`; otherwise
  marimo's MCP endpoint refuses non-localhost requests, breaking the
  charly host-port-rewrite path

## mo.iframe pattern for inline HTML rendering

Marimo cells display the value of the **last expression** in the cell
body. To render a string of HTML (e.g. a custom MapLibre map) inside
the notebook output area, use:

```python
import marimo as mo
mo.iframe(html_string, height="500px")
```

`mo.iframe` wraps the HTML in a sandboxed `<iframe srcdoc>` that
loads in the marimo UI. Used by the streets MapLibre cell in
`/charly-versa:notebook-osm` to render martin's vector tiles
(folium's TileLayer can't decode PBF).

For folium maps that DON'T need iframe wrapping, return the
`folium.Map` instance as the cell's last expression. The trust-wrapper
bypass is documented in `/charly-versa:notebook-osm`.

## Cell-display gotcha

Marimo's "display value" is the cell's **last expression**, NOT the
return value. An assignment is a statement — it has no display value:

```python
# WRONG — cell displays nothing
@app.cell
def __():
    df = pl.scan_parquet("...").collect()
    return df,                            # exports df, but no display

# RIGHT — bare expression is the display value
@app.cell
def __():
    df = pl.scan_parquet("...").collect()
    df                                     # marimo displays this
    return df,
```

## Marimo session persistence (gotcha)

When a marimo session is open and the file on disk changes (e.g.
`charly update --force-seed` rewrites the notebook), marimo re-persists
the file with its session's cell order, NOT the new file's order.
Symptom: cells appear in scrambled order in the editor; markdown
header lands at the bottom; etc.

Surgical reset (kill marimo, restore from `/data/`, restart):

```bash
charly service stop versa marimo
charly cmd versa "cp /data/workspace/notebooks/osm-monaco-viz.py \
     /workspace/notebooks/osm-monaco-viz.py"
charly service start versa marimo
```

Then the user reloads their browser tab (the old session's WebSocket
is dead after the restart anyway).

## Cross-references

- `/charly-versa:versa` — the image that composes this layer
- `/charly-versa:versa-mcp` — the MCP server tool catalog
- `/charly-versa:notebook-osm` — the canonical notebook using this env
- `/charly-distros:cuda` — required dep
- `/charly-infrastructure:supervisord` — required dep
- `/charly-image:layer` — layer authoring conventions
