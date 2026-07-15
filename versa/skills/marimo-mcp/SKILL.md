---
name: marimo-mcp
description: |
  marimo's built-in MCP server (10 read-only inspection tools — get_active_notebooks, get_cell_outputs, get_notebook_errors, etc.) at port 2718 path /mcp/server.
  Use when working with the marimo MCP tool catalog, programmatic notebook diagnostics, or the cells-don't-execute-via-MCP gap (marimo MCP is read-only; cells run via WebSocket from a browser OR `marimo export ipynb --include-outputs` for headless execution).
---

# marimo-mcp — marimo's built-in MCP server (read-only inspection)

marimo's notebook server has a built-in MCP endpoint enabled by the
`--mcp` flag (see `/charly-versa:marimo-layer` service spec). It serves
10 inspection tools for diagnosing active notebook sessions —
**read-only**: cells cannot be executed via this MCP. Execution
requires a browser-attached WebSocket session OR
`marimo export ipynb --include-outputs` for headless runs.

## URL pattern

```
http://{{.ContainerName}}:2718/mcp/server   # in-pod
http://localhost:22718/mcp/server           # host-side (mapped port)
```

Transport: Streamable HTTP. Registered in this plugin's `.mcp.json`
as the `marimo` server.

## Tool catalog (10 tools)

All tools are **read-only**. Each takes an `args` JSON object as
the sole parameter (often `{}` or `{"session_id": "..."}`).

| Tool | Purpose |
|---|---|
| `get_marimo_rules` | Returns the official marimo rules for you |
| `get_active_notebooks` | Lists currently-open notebooks + session IDs + active connection counts |
| `get_lightweight_cell_map` | Per-cell preview (cell_id, line_count, runtime_state, has_output, has_errors) for a session |
| `get_cell_runtime_data` | Full runtime data for one or more cells: code, errors, declared variables |
| `get_cell_outputs` | Cell execution outputs (visual display + console streams) |
| `get_tables_and_variables` | All tables and variables visible in a session |
| `get_database_tables` | Database table info (regex query supported) |
| `get_notebook_errors` | All errors in a session, organised by cell |
| `lint_notebook` | Lint a marimo notebook for issues |
| `get_cell_dependency_graph` | Cell dependency graph (variable-flow edges) |

## Why no execute tool

marimo's reactive runtime executes cells based on dependency-graph
analysis when variable values change in the editor. The MCP exposes
a *read* surface against an active session — there's no "run cell N"
RPC because that's not how marimo orchestrates cells.

Two paths to execute notebook content programmatically:

1. **Browser-attached run** — open the notebook in a browser; marimo
   reactively runs all reachable cells. The marimo MCP can then read
   the session state (cell outputs, errors, variables).

2. **Headless export** — `marimo export ipynb --include-outputs` runs
   every cell server-side and writes a Jupyter notebook with embedded
   outputs. Used in this repo's R10 acceptance for the
   osm-monaco-viz.py notebook:

   ```bash
   charly cmd versa "/home/user/.pixi/envs/default/bin/marimo \
     export ipynb /workspace/notebooks/osm-monaco-viz.py \
     --include-outputs --sort topological -o /tmp/notebook-run.ipynb -f"
   ```

   Requires `nbformat` in the pixi env (already pinned in
   `candy/marimo/pixi.toml`).

## Verification

Run the candy's baked `mcp:` steps (ping + catalog enumeration) against a live
deployment — the `mcp:` check verb is declarative-only, served out-of-process by
`candy/plugin-mcp` (there is no host `charly check` subcommand for it):

```bash
charly check live versa --filter mcp   # runs the baked mcp: ping / list-tools steps (mcp_name: marimo)
```

Author them as declarative steps on the candy:

```yaml
marimo-mcp-ping:
    check: the marimo mcp server responds to ping
    mcp: ping
    mcp_name: marimo
    context: [deploy]
marimo-mcp-list-tools:
    check: the marimo mcp server lists its tools
    mcp: list-tools
    mcp_name: marimo
    context: [deploy]
```

For an ad-hoc, multi-call diagnostic (e.g. `get_active_notebooks` → extract a
`session_id` → `get_lightweight_cell_map`) the declarative verb has no cross-call
state chaining; point an external MCP client (`/charly-tools:mcporter`) at the
server's published host port instead.

## MCP name decoupling

The MCP server name `marimo` is the service contract — declared in
`candy/marimo/charly.yml` `mcp_provide.name: marimo`. This plugin's
`.mcp.json` keys off the same name. Renames of the layer / Python
package / image MUST NOT change this name unless the contract is
explicitly broken in a hard cutover.

## Cross-references

- `/charly-versa:marimo-layer` — layer that runs the server
- `/charly-versa:airflow-layer` — Airflow service in the same pod; it has no MCP wrapper
- `/charly-versa:notebook-osm` — example notebook diagnosed via this MCP
- `/charly-build:charly-mcp-cmd` — MCP probe verb authoring + URL rewriter
- `/charly-check:check` — `mcp:` declarative check-verb reference
