# charly-versa

MCP server registration + skill coverage for the **versa** image — a
marimo reactive notebooks + Apache Airflow (LocalExecutor + SQLite) +
OSM/GTFS analytics pipeline (quackosm + tippecanoe + martin vector
tiles + MapLibre GL JS with 3D terrain) + transit visualisation
(gtfs-parquet + folium) bundle.

This plugin exposes **two** MCP servers to Claude Code:

- `marimo` — 10 read-only inspection tools at `http://localhost:22718/mcp/server`
  (notebook session diagnostics: cell outputs, runtime data, dependency
  graph, errors)
- `airflow` — ~70 REST-API-wrapping tools at `http://localhost:29999/mcp`
  (DAG management: fetch_dags, post_dag_run, get_dag_run, list_connections,
  …)

URLs use the **host-visible** ports from the `versa` deploy
entry (Claude Code runs on the host). Container-internal ports
(`2718`, `19999`) are only reachable from inside the pod.

## Contents

- `.claude-plugin/plugin.json` — plugin metadata
- `.mcp.json` — registration of both MCP servers
- `README.md` — this file
- `skills/<name>/SKILL.md` — 16 skills covering the versa ecosystem

## Skills

| Skill | Kind | Coverage |
|---|---|---|
| `versa` | image | top-level versa image — composition, ports, env vars, R10 acceptance |
| `marimo-layer` | layer | marimo runtime — pixi env, supervisord service, mo.iframe pattern |
| `marimo-mcp` | mcp server | the 10 marimo MCP tools + execution gap |
| `airflow-layer` | layer | Airflow 3.x compatibility (8 surfaced bugs from RCA) |
| `airflow-mcp` | mcp server | mcp-server-apache-airflow tools + JWT auth flow |
| `notebook-osm` | data layer | the six-DAG OSM + GTFS + 4-pipeline-comparison + shortbread notebook architecture |
| `maputnik-layer` | layer | maputnik build with Vite `--base=/` override |
| `pmtiles-viewer` | layer | protomaps/PMTiles /app SPA on port 28001 — visual inspector for the four sibling PMTiles archives the image produces |
| `shortbread` | layer | tilemaker (C++) + shortbread-tilemaker Lua config; produces shortbread-schema vector tiles |
| `versatiles` | layer | versatiles-rs CLI (convert/serve/probe) + `versatiles serve` supervisord service on port 28090 |
| `versatiles-style` | layer | @versatiles/style MapLibre style generator (colorful/eclipse/graybeard/...) bundled locally |
| `versatiles-fonts` | layer | SDF font glyph PBFs (Noto Sans + 9 others) for MapLibre rendering |
| `maplibre-versatiles-styler` | layer | interactive MapLibre control widget for switching versatiles styles + recoloring + exports |
| `versatiles-frontend` | layer | versatiles-org/versatiles-frontend SPA on port 28002; also re-exports versatiles-style / fonts / styler at `/style/`, `/fonts/`, `/styler/` |
| `osm-tools-layer` | layer | tippecanoe + martin + DAG-completion reload pattern + four sibling sources |
| `debug-tools-layer` | layer | 49-tool distro-agnostic debug toolkit |

## Requirements

- A `versa` container must be **running** before Claude Code starts.
  See `/charly-versa:versa`.
- Claude Code registers MCP servers at **session start**. If the
  versa container is launched *after* Claude Code, the auto-connect
  to `localhost:22718/mcp/server` and `localhost:29999/mcp` fails
  silently and the `mcp__marimo__*` / `mcp__airflow__*` tools will not
  appear in the session's tool catalog. **Restart Claude Code after the
  container is up** to pick up the registration.

## MCP Name Decoupling

The MCP server names `marimo` and `airflow` are deliberately stable
across renames of the underlying layer / Python package / image. The
service contract is the `mcp_provide.name:` field in
`candy/marimo/charly.yml` and `candy/airflow/charly.yml`. Consumers
(this plugin's `.mcp.json`, plus any in-image MCP client) all key off
those names — not off layer/package/image names — so renames don't
ripple into client code. This decoupling is the reason the 2026-05
image rename (`marimo` → `versa`) did NOT touch the MCP server name.

## Cross-pod use

In single-pod deployments (the default) `airflow` runs alongside
`marimo` inside the versa container. For cross-pod topologies —
separate `airflow-pod` reachable via the shared `charly` podman network —
the notebook reads `AIRFLOW_API_INTERNAL_URL` from env (defaults
`http://localhost:8080`; override to `http://airflow-pod:8080`).
The marimo notebook's self-authored DAG goes into the shared
`workspace` volume that both pods mount, so DAG drop + scheduler
pickup work identically. See `/charly-versa:versa` "Cross-pod
topology" for the full operator recipe.

## Related skills

- `/charly-versa:versa` — the image (start here)
- `/charly-versa:marimo-layer` — marimo's pixi env + service spec
- `/charly-versa:marimo-mcp` — the marimo MCP server's tool catalog
- `/charly-versa:airflow-layer` — Airflow 3.x layer wiring + auth
- `/charly-versa:airflow-mcp` — the airflow MCP server's tool catalog
- `/charly-versa:notebook-osm` — the dual-DAG OSM+GTFS notebook
- `/charly-versa:maputnik-layer` — maputnik static-style editor
- `/charly-versa:osm-tools-layer` — martin + tippecanoe + reload pattern
- `/charly-versa:debug-tools-layer` — the debug toolkit composed by this image
