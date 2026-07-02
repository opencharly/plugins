---
name: versatiles-frontend
description: |
  VersaTiles Frontend — pre-built TypeScript SPA from versatiles-org/versatiles-frontend GitHub releases. Third static-SPA-via-python-http.server in the versa image (after maputnik + pmtiles-viewer). Served on port 8002 (host-mapped 28002). Also re-exports the versatiles-style layer's bundle at /style/ so the notebook's mo.iframe can reach it via an absolute URL.
  MUST be invoked before building, deploying, or troubleshooting the versatiles-frontend layer.
---

# versatiles-frontend — VersaTiles tile-content explorer SPA

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord`, `versatiles-style` (re-exported under `/style/`) |
| Distros | `arch` + `fedora` |
| Build deps | curl, jq |
| Ports | `8002` (host-mapped to **28002**) |
| Service | `versatiles-frontend` (supervisord, `restart: always`, priority 38) |
| Static dist | `/opt/versatiles-frontend/` |

## Why pre-built tarball (not npm build)

versatiles-org/versatiles-frontend ships pre-built static SPAs on
every release (four variants: `frontend`, `frontend-dev`,
`frontend-min`, `frontend-tiny`). We pick `frontend` (full feature
set) since the versa image targets interactive exploration, not
minimal embedding. Build deps (`nodejs`, `npm`, `vite`) are NOT
needed inside the versa image — saves ~250 MB image size.

This contrasts with `/charly-versa:maputnik-layer` which DOES build
from source (`npm ci` + `npm run build -- --base=/`) because
maputnik ships no pre-built tarball.

## Service spec

```yaml
service:
  - name: versatiles-frontend
    exec: /usr/bin/python3 -m http.server 8002 --directory /opt/versatiles-frontend
    restart: always
    working_directory: /opt/versatiles-frontend
    priority: 38
    enable: true
    scope: system
```

Mirrors maputnik (priority 34) and pmtiles-viewer (priority 35). All
three are stdlib python3 http.server processes — no shared
infrastructure, easy to debug independently.

## Bundle layout

After the install task completes, `/opt/versatiles-frontend/`
contains:

| Path | Source |
|---|---|
| `index.html` | unpacked from `frontend.tar.gz` |
| `assets/`, `tile-data/`, ... | unpacked from `frontend.tar.gz` |
| `style/versatiles-style.js`, `style/...` | copied from `/opt/versatiles-style/` so the notebook's iframe can import the bundle via the same http.server |

The cross-layer dependency on versatiles-style is declared via
`require: [supervisord, versatiles-style]` — image-build ordering
ensures versatiles-style runs first and populates
`/opt/versatiles-style/` before this layer's `cp -r` copies it
under `/opt/versatiles-frontend/style/`.

## Check probes

Build-scope:
- `versatiles-frontend-index-html` — `/opt/versatiles-frontend/index.html` exists
- `versatiles-frontend-style-bundle` — `find /opt/versatiles-frontend/style -name 'versatiles-style*.js' -size +1c` matches (verifies the cross-layer cp ran)

Deploy-scope:
- `versatiles-frontend-running` — supervisord service RUNNING
- `versatiles-frontend-port-reachable` — TCP 8002 reachable
- `versatiles-frontend-http-up` — `GET /` returns 200
- `versatiles-frontend-style-fetchable` — `curl http://localhost:8002/style/` returns success (the directory listing or index file)

## Use case in the versa image

Operator opens `http://127.0.0.1:28002/` in a browser to:

1. **Explore tile contents** from any local versatiles serve or
   PMTiles archive. The frontend includes interactive map widgets,
   metadata inspection, and tile-layer toggles.
2. **Test custom styles** before pasting into the notebook's
   shortbread MapLibre cell.

The frontend ALSO serves the versatiles-style bundle at `/style/`,
which is the load path the notebook's iframe uses. This is a
secondary role of the same http.server — operators don't need to
visit `/style/` directly.

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:versatiles` — the tile-server backend the frontend
  connects to by default
- `/charly-versa:versatiles-style` — the bundle re-exported under `/style/`
- `/charly-versa:pmtiles-viewer` — sibling static-SPA layer (port 28001)
- `/charly-versa:maputnik-layer` — sibling static-SPA layer (port 28000)
- `/charly-versa:notebook-osm` — the shortbread MapLibre cell that loads
  the re-exported versatiles-style bundle via this layer's http.server
