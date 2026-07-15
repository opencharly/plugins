---
name: versatiles-style
description: |
  The @versatiles/style TypeScript package generates MapLibre style JSON for Shortbread vector tiles. Its local browser bundle avoids a CDN and is re-exported at /style/ for notebook iframe access.
  MUST be invoked before building, deploying, or troubleshooting the versatiles-style layer.
---

# versatiles-style — MapLibre style generator for Shortbread

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` (transitive; no service of its own) |
| Distros | `arch` + `fedora` |
| Build deps | nodejs, npm |
| Install path | `/opt/versatiles-style/` |
| Re-exported at | `/opt/versatiles-frontend/style/` (by the versatiles-frontend layer) |

## What it generates

`versatiles-style` ships six style generators, all targeting the
Shortbread vector-tile schema:

| Function | Output character |
|---|---|
| `colorful({ language })` | Vivid colors, full feature set |
| `eclipse({ language })` | Dark theme |
| `graybeard({ language })` | Grayscale |
| `neutrino({ language })` | Minimal / blueprint style |
| `shadow({ language })` | Subtle hillshade-friendly |
| `satellite({ language })` | Satellite-imagery overlay style |

Each returns a MapLibre style JSON object (`style.version`, `.sources`,
`.layers`, `.glyphs`, `.sprite`). The default source URL points at
`tiles.versatiles.org`; the notebook patches `style.sources.versatiles.tiles`
to our local versatiles serve.

## Why install locally

The package's README documents both an npm-install path and a
standalone GitHub release tarball. We prefer the GitHub release
tarball (`versatiles-style.tar.gz`) because it ships the browser-
ready bundle directly. The layer has a two-tier install:

1. **Tier 1**: download `versatiles-style.tar.gz` from the latest
   GitHub release and extract to `/opt/versatiles-style/`.
2. **Tier 2** (fallback): `npm install @versatiles/style` and copy
   `node_modules/@versatiles/style/release/` (or the whole package
   if `release/` is missing) to `/opt/versatiles-style/`.

The fallback covers cases where the GitHub release is missing the
expected tarball asset.

## Iframe-access pattern

The notebook's shortbread MapLibre cell uses `mo.iframe`, whose
`srcdoc` HTML can only fetch absolute URLs (not server-relative
paths against the marimo edit server). The bundle is re-exported
at `/opt/versatiles-frontend/style/versatiles-style.js` by the
versatiles-frontend layer's `python -m http.server`, so the
iframe references:

```html
<script src="http://127.0.0.1:28002/style/versatiles-style.js"></script>
```

Single-origin against the versatiles-frontend service avoids
cross-origin CORS issues that would otherwise need explicit
`Access-Control-Allow-Origin: *` headers.

## Check probes

Build-scope:
- `versatiles-style-bundle-present` — `find /opt/versatiles-style -maxdepth 3 -name 'versatiles-style*.js' -size +1c` matches at least one non-empty file (the install path's exact filename depends on package version; the find pattern is lenient)

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:versatiles` — the tile-server backend the generated
  styles point at after URL patching
- `/charly-versa:versatiles-frontend` — re-exports this bundle at
  `/style/` for iframe consumption
- `/charly-versa:shortbread` — the tile schema the styles render
- `/charly-versa:notebook-osm` — the shortbread MapLibre cell that
  imports `colorful()` from the bundle
