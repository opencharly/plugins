---
name: fedora-nonfree
description: |
  Fedora with RPM Fusion non-free repositories enabled. Base for boxes
  needing codec or proprietary package support like immich.
  MUST be invoked before building, deploying, configuring, or troubleshooting the fedora-nonfree box.
---

# fedora-nonfree

Fedora base with RPM Fusion free and non-free repositories enabled.

**Owned by the `opencharly/distro-fedora` submodule.** Lives bare-local in the
**`opencharly/distro-fedora`** submodule (mounted at `box/fedora`), alongside
`/charly-distros:fedora` + `/charly-distros:fedora-builder`; the submodule is
SELF-CONTAINED (`import: []`). Its consumers (`/charly-immich:immich`,
`/charly-distros:nvidia`) live in the same submodule and base on it as a
bare-local `fedora-nonfree`. Its `rpmfusion`
candy is pinned as a github ref so the same definition resolves in both main and
the submodule.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Layers | rpmfusion |
| Platforms | linux/amd64 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` (quay.io/fedora/fedora:43)
2. `rpmfusion` — RPM Fusion free + non-free repos

## Quick Start

```bash
charly box build fedora-nonfree
charly shell fedora-nonfree
```

## Key Candies

- `/charly-distros:rpmfusion` — RPM Fusion repository configuration

## Derived Boxes

- `/charly-immich:immich` — photo management with codec support

## Related Boxes

- `/charly-distros:fedora` — parent base (without non-free repos)

## Verification

After `charly box build`:
- `charly box list` — box appears in list
- `charly shell fedora-nonfree` — interactive shell works

## When to Use This Skill

**MUST be invoked** when the task involves the fedora-nonfree box, RPM Fusion support, or non-free codec packages. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
