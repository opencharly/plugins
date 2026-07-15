---
name: maplibre-versatiles-styler
description: |
  maplibre-versatiles-styler is an interactive MapLibre control for switching presets, editing palettes, recoloring, fonts, language, satellite settings, and exporting style JSON. The local npm bundle avoids a CDN and is re-exported at /styler/.
  MUST be invoked before building, deploying, or troubleshooting the maplibre-versatiles-styler layer.
---

# maplibre-versatiles-styler — interactive style-switcher control

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` (transitive; no service of its own) |
| Distros | `arch` + `fedora` |
| Build deps | nodejs, npm, curl, jq |
| Install path | `/opt/maplibre-versatiles-styler/` |
| Re-exported at | `/opt/versatiles-frontend/styler/` (by the versatiles-frontend layer) |

## Usage pattern (in the notebook cell)

```javascript
// Loaded via <script src="/styler/maplibre-versatiles-styler.umd.js" defer></script>
window.addEventListener('load', () => {
  if (window.VersaTilesStylerControl) {
    map.addControl(new window.VersaTilesStylerControl({ open: false }));
  }
});
```

The control attaches as a MapLibre `IControl` and renders a sidebar
widget on the right edge of the map. Operators can:

- Click a preset (colorful, eclipse, graybeard, …) to swap styles
- Adjust a color picker to recolor the entire map palette
- Change the label language (overrides the `language: 'en'` option
  passed to the style generator at construction time)
- Toggle satellite-imagery layers
- Copy the resulting style JSON to clipboard for use in other tools

## Two-tier install

Same pattern as `/charly-versa:versatiles-style`:

1. **Tier 1**: GitHub release tarball if available.
2. **Tier 2** (fallback): `npm install maplibre-versatiles-styler` and
   copy the package's `dist/` directory.

The check probe is lenient about the exact filename (the package
ships both ESM and UMD builds across multiple paths) — it asserts
that at least one non-empty `*.js` file exists under
`/opt/maplibre-versatiles-styler/`.

## Check probes

Build-scope:
- `maplibre-versatiles-styler-bundle-present` — at least one non-empty `*.js` file exists under `/opt/maplibre-versatiles-styler/`

## Cross-references

- `/charly-versa:versa` — image composing this layer
- `/charly-versa:versatiles-style` — the style generator whose output
  this control mutates at runtime
- `/charly-versa:versatiles-fonts` — the font bundle the control's
  language-switcher references
- `/charly-versa:versatiles-frontend` — re-exports this bundle at `/styler/`
- `/charly-versa:notebook-osm` — the shortbread MapLibre cell that
  attaches this control to its map instance
