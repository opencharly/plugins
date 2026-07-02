---
name: maputnik-layer
description: |
  Maputnik — visual editor for MapLibre GL vector-tile styles. Pure-JS SPA built from upstream source via npm at image build time, served as static dist by python -m http.server. Pairs with osm-tools's martin tile server.
  Use when working with the maputnik layer, the Vite --base=/ build override (critical fix; default --base=/maputnik/ produces 404 asset paths), or the asset-base lock-in check test.
---

# maputnik — visual MapLibre style editor

Maputnik is a pure-JS SPA for visually editing MapLibre GL JS style
JSON files. Built from upstream source (`felt/maputnik`) via npm at
image build time, served as a static dist by Python's stdlib
`http.server`. Composed by `/charly-versa:versa` so operators can
iterate on the streets-map style against the in-pod martin tile
server (`/charly-versa:osm-tools-layer`).

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Distros | `fedora` (sole; needs node + npm + git for build) |
| Build deps | nodejs, npm, git |
| Ports | `8000` (host-mapped to **28000**) |
| Service | `maputnik` (supervisord, `restart: always`) |
| Static dist | `/opt/maputnik/build/` (Vite `dist/` renamed) |

## Service spec

```yaml
maputnik-service:
  service:
    - name: maputnik
      exec: /usr/bin/python3 -m http.server 8000 --directory /opt/maputnik/build
      restart: always
      working_directory: /opt/maputnik
```

Pure stdlib server — no marimo-pixi-env coupling. The system
`python3` from supervisord's own RPM dep handles the static serve.

## Critical: Vite --base=/ override

Maputnik's `package.json` defines `"build": "tsc && vite build"`.
Vite's default base path for builds is `--base=/maputnik/`. That
default bakes `/maputnik/assets/*` URL references into the emitted
`index.html` — but we serve the dist at root (`/`) via
`python -m http.server`, so all those baked URLs **404 in the
browser**.

Symptom (before fix): the maputnik UI loads at
`http://127.0.0.1:28000/` showing a blank page; browser dev-tools
shows asset 404s for `/maputnik/assets/index-*.js` etc.

**Fix in the build cmd**:

```yaml
maputnik-step-build:
  run: build maputnik from upstream source with the Vite --base=/ override
  command: |
    set -euo pipefail
    git clone --depth 1 https://github.com/maplibre/maputnik /tmp/maputnik
    cd /tmp/maputnik
    npm ci --no-audit --no-fund
    # Override Vite's default --base=/maputnik/ so asset URLs are
    # root-relative and resolve against our serve path. The `--`
    # forwards the flag through npm to vite.
    npm run build -- --base=/
    if [ -d dist ]; then
      mkdir -p /opt/maputnik
      cp -r dist /opt/maputnik/build
    else
      echo "maputnik build did not produce ./dist directory" >&2
      ls -la
      exit 1
    fi
    cd /
    rm -rf /tmp/maputnik /root/.npm
  run_as: root
```

## Check lock-in

A deploy-context `check:` step greps the served HTML for the
(forbidden) `/maputnik/` prefix and fails if present. It is a `check:`
step, so it is a deterministic
acceptance step that locks in the fix against a future revert to the
Vite default. The step is a child step node of the candy, named by its
`id:`:

```yaml
maputnik-asset-base-not-prefixed:
  check: maputnik serves a root-relative SPA
  id: maputnik-asset-base-not-prefixed
  command: |
    ! curl -fsS http://localhost:8000/ | grep -q '"/maputnik/'
  in_container: true
  exit_status: 0
  context:
    - deploy
```

Plus the standard probe steps (also `context: [deploy]`):

- `maputnik-running` — supervisord program is RUNNING
- `maputnik-port-reachable` — TCP 8000 reachable
- `maputnik-http-up` — `GET /` returns 200

## Use case in versa

The streets-map style in `/charly-versa:notebook-osm` cell 7 is a
small inline JSON. Operators iterating on richer styles can:

1. Open maputnik at `http://127.0.0.1:28000/`
2. Connect to martin's TileJSON URL `http://127.0.0.1:23000/monaco`
3. Visually edit polygon/line/circle layer paint properties
4. Export the style JSON
5. Paste into the notebook cell (or save to a server-mounted file
   and load via `style: 'http://...'` in the MapLibre constructor)

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:osm-tools-layer` — companion martin tile server
- `/charly-versa:notebook-osm` — uses an inline style; maputnik can author richer ones
- `/charly-infrastructure:supervisord` — service runtime
