---
name: sway-browser-ecovoyage
description: Sway-browser-vnc instance wired to versa/ecovoyage tailnet URLs — chrome-devtools-mcp + CDP for debugging the generated MapLibre + folium maps.
---

# sway-browser-ecovoyage — chrome-devtools-mcp debug bed for versa/ecovoyage maps

Deploys `sway-browser-vnc` as a pinned Pattern A instance
(`sway-browser-vnc/ecovoyage`) preconfigured to debug the maps
rendered by the `versa/ecovoyage` notebook (`osm-monaco-viz.py`).
The pod's chrome-devtools-mcp + raw CDP + VNC ports are all exposed
on the host's existing tailnet identity (`ac.armadillo-quail.ts.net`)
so external Claude Code / agents — and you —
can drive Chrome programmatically over Streamable HTTP MCP.

## Why this exists

The `versa/ecovoyage` notebook generates 5 client-rendered maps
(4 MapLibre via `martin`, 1 shortbread via `versatiles`, 1 folium).
Verifying these from a sandboxed agent context requires a browser
that can reach the dynamic tile URLs (e.g.
`https://ac.armadillo-quail.ts.net:33000/monaco/{z}/{x}/{y}`).

The existing `check-sway-browser-vnc-pod` is general-purpose and
isn't preconfigured with the ecovoyage URLs — and its loopback
isn't the same loopback as the host, so 127.0.0.1 references to
versa/ecovoyage's host ports don't resolve. Tailnet URLs solve
both problems: same identity from any device on the tailnet, no
loopback collision, TLS-terminated by tailscaled.

## Deploy

```bash
charly config sway-browser-vnc/ecovoyage
charly start sway-browser-vnc/ecovoyage
```

The deploy entry is fully specified in `~/.config/charly/charly.yml` —
it pins host ports (5901 VNC, 9230 CDP, 9232 MCP) and forwards
every `*_PUBLIC_URL` env var so chrome's address bar + scripts
+ chrome-devtools-mcp tooling all see the same tailnet URLs the
versa/ecovoyage notebook embeds in its MapLibre HTML.

## URL inventory

### Inbound — debug-bed services exposed on tailnet

| Endpoint | Tailnet URL | What it is |
|---|---|---|
| chrome-devtools-mcp | `https://ac.armadillo-quail.ts.net:9232/mcp` | Streamable HTTP MCP, 29 tools |
| Chrome DevTools raw | `https://ac.armadillo-quail.ts.net:9230` | CDP `/json/version` etc. |
| VNC | `tcp://ac.armadillo-quail.ts.net:5901` | wayvnc, no auth |

### Outbound — versa/ecovoyage tailnet URLs the browser will load

These are passed in as env vars (`MARTIN_PUBLIC_URL`,
`AIRFLOW_PUBLIC_URL`, etc.) so chrome scripts can use them via
`process.env` or via the supervisord-launched `VERSA_ECOVOYAGE_MARIMO_URL`:

| Var | Tailnet URL |
|---|---|
| `VERSA_ECOVOYAGE_MARIMO_URL` | `https://ac.armadillo-quail.ts.net:32718/?file=notebooks/osm-monaco-viz.py` |
| `MARTIN_PUBLIC_URL` | `https://ac.armadillo-quail.ts.net:33000` |
| `AIRFLOW_PUBLIC_URL` | `https://ac.armadillo-quail.ts.net:38080` |
| `PMTILES_VIEWER_PUBLIC_URL` | `https://ac.armadillo-quail.ts.net:38001` |
| `VERSATILES_PUBLIC_URL` | `https://ac.armadillo-quail.ts.net:38090` |
| `VERSATILES_ASSETS_PUBLIC_URL` | `https://ac.armadillo-quail.ts.net:38002` |
| `VERSATILES_STYLE_PUBLIC_URL` | `https://ac.armadillo-quail.ts.net:38002/style` |

## Map-debug recipe

Author the recipe as ordered `cdp:` plan steps (the `cdp:` verb is served
out-of-process by candy/plugin-cdp) and run them with
`charly check live sway-browser-vnc/ecovoyage --filter cdp`:

```yaml
# 1. Open the marimo notebook in chrome
map-open:
    run: open the marimo notebook
    cdp: open
    context: [deploy]
    url: "https://ac.armadillo-quail.ts.net:32718/?file=notebooks/osm-monaco-viz.py"
# 2. Run all stale cells (after the DAGs finish executing)
map-run-cells:
    run: click every run-button
    cdp: eval
    context: [deploy]
    tab: "1"
    expression: 'document.querySelectorAll("button[data-testid=run-button]").forEach(b => b.click())'
# 3. Wait for the streets MapLibre canvas to appear
map-wait-canvas:
    check: the MapLibre canvas appears
    cdp: wait
    context: [deploy]
    tab: "1"
    selector: ".maplibregl-canvas"
    timeout: 90s
# 4. Screenshot — validate dimensions + non-uniform content
map-screenshot:
    check: the streets map renders real, non-uniform content
    cdp: screenshot
    context: [deploy]
    tab: "1"
    artifact: /tmp/ecovoyage-streets.png
    artifact_min_bytes: 50000
    artifact_min_dimensions: 800x600
    artifact_not_uniform: true
# 5. Inspect the iframe contents directly (catch JS errors before they
#    silently produce blank canvases — see the hyphen-in-JS-identifier
#    bug story below)
map-inspect-iframes:
    check: the iframe canvases are populated
    cdp: eval
    context: [deploy]
    tab: "1"
    expression: |
        [...document.querySelectorAll("iframe")].map(f => ({
          src: f.src, canvas: !!f.contentDocument?.querySelector("canvas"),
          consts: [...(f.contentDocument?.body?.innerHTML?.matchAll(/const map_[a-z_-]+/g) || [])].map(m=>m[0])
        }))
```

## chrome-devtools-mcp from external Claude Code

The `chrome-devtools-mcp` server's MCP endpoint is published on the
tailnet so any Claude Code instance — local or remote on the tailnet —
can plug it into its MCP config:

```jsonc
// .mcp.json
{
  "mcpServers": {
    "chrome-devtools-ecovoyage": {
      "url": "https://ac.armadillo-quail.ts.net:9232/mcp",
      "transport": "http"
    }
  }
}
```

In opencharly's `provides:` registry this server is published as
`chrome-devtools-ecovoyage` (instance-suffixed by `charly config`'s
MCP name-disambiguation rule — see `/charly-core:deploy`) so it
doesn't collide with the `check-sway-browser-vnc-pod`'s base
`chrome-devtools` provide.

## Hard-won lessons (carried over from this skill's authoring session)

### Iframe canvas check beats iframe count

When verifying that maps render, count the **canvas elements inside
each iframe**, not just the iframes themselves. A failed `const map_…`
declaration leaves the iframe with its `<script>` tag present but no
canvas — and the iframe count is unchanged. The right check:

```js
[...document.querySelectorAll("iframe")].map(f => ({
  canvas: !!f.contentDocument?.querySelector("canvas")
}))
```

A `canvas: false` row for a map cell is the signal that MapLibre
threw during init. Pull the script body and grep for invalid
identifiers (hyphens in `const` names was the canonical bug:
`const map_duckdb-mvt = …` parses as `map_duckdb − mvt`).

### Container chrome ≠ host chrome on `127.0.0.1`

If you debug from a container-sandboxed chrome
(e.g. `check-sway-browser-vnc-pod`), `127.0.0.1` is **that pod's
loopback**, not the host's. Maps with `http://127.0.0.1:<host-port>`
tile URLs will silently fail to fetch tiles even though MapLibre
instantiates the canvas. This is why every `*_PUBLIC_URL` env var
should be **tailnet-form** for browser-side consumption — tailnet
URLs are the same from anywhere on the tailnet, including
sandboxed pods.

## Related

- `/charly-versa:notebook-osm` — the marimo notebook whose 5 maps this skill exists to debug
- `/charly-versa:versa` — the image hosting the maps (versa/ecovoyage = Pattern A instance)
- `/charly-selkies:sway-browser-vnc` — the base image this deploy instantiates
- `/charly-selkies:chrome-devtools-mcp` — the layer providing the MCP server
- `/charly-check:cdp` — the verb catalog driving Chrome
- `/charly-build:charly-mcp-cmd` — verifying the MCP endpoint via the `mcp:` check verb (`charly check live <image> --filter mcp`)
- `/charly-core:deploy` — Pattern A multi-instance + MCP name disambiguation
- `/charly-automation:sidecar` — alternative tailscale sidecar pattern (not used here; this skill uses host-serve)
