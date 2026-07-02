---
name: versatiles-fonts
description: |
  VersaTiles SDF font glyphs for MapLibre GL JS. 10 font families (Fira Sans, Lato, Libre Baskerville, Merriweather Sans, Noto Sans, Nunito, Open Sans, PT Sans, Roboto, Source Sans 3) bundled locally from versatiles-org/versatiles-fonts GitHub releases. Installed so the notebook's shortbread MapLibre cell renders labels without hitting tiles.versatiles.org as a runtime font CDN. Re-exported by the versatiles-frontend layer's http.server at /fonts/.
  MUST be invoked before building, deploying, or troubleshooting the versatiles-fonts layer.
---

# versatiles-fonts — SDF glyph PBFs for MapLibre

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` (transitive; no service of its own) |
| Distros | `arch` + `fedora` |
| Build deps | curl, jq |
| Install path | `/opt/versatiles-fonts/` |
| Re-exported at | `/opt/versatiles-frontend/fonts/` (by the versatiles-frontend layer) |

## What it ships

`versatiles-org/versatiles-fonts` releases a `fonts.tar.gz` containing
all 10 font families pre-rendered as SDF (signed distance field) PBFs
that MapLibre GL JS can fetch via its standard glyph URL template:

```
{glyphs}/{fontstack}/{range}.pbf
```

The directory layout inside the tarball (verified at install time):

```
versatiles-fonts/
├── Fira Sans Regular/
│   ├── 0-255.pbf
│   ├── 256-511.pbf
│   └── ...
├── Noto Sans Regular/
│   ├── 0-255.pbf
│   └── ...
├── Roboto Regular/
│   └── ...
└── ...
```

## MapLibre glyphs URL pattern

The notebook's shortbread cell patches the style's glyphs URL:

```javascript
style.glyphs = 'http://127.0.0.1:28002/fonts/{fontstack}/{range}.pbf';
```

MapLibre substitutes `{fontstack}` (e.g. `Noto Sans Regular`) and
`{range}` (e.g. `0-255`) when fetching each glyph range as the user
pans/zooms. The versatiles-frontend http.server serves the files
directly — no special URL rewriting needed.

## Check probes

Build-scope:
- `versatiles-fonts-bundle-present` — at least one `*.pbf` glyph file exists under `/opt/versatiles-fonts/`
- `versatiles-fonts-noto-sans` — `Noto Sans Regular` family is present (sanity check that the tarball wasn't a partial variant)

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:versatiles-style` — sibling MapLibre style generator; the generated styles reference the glyph URL pattern this layer provides
- `/charly-versa:versatiles-frontend` — re-exports this bundle at `/fonts/`
- `/charly-versa:maplibre-versatiles-styler` — UI control that lets users switch between font families exposed by this layer
- `/charly-versa:notebook-osm` — the shortbread MapLibre cell that patches `style.glyphs` to point at this layer's bundle
