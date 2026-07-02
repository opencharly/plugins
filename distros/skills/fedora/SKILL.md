---
name: fedora
description: |
  Base Fedora 43 image. Root of the box hierarchy for all RPM-based boxes.
  MUST be invoked before building, deploying, configuring, or troubleshooting the fedora box.
---

# fedora

Root base image built from `quay.io/fedora/fedora:43`. Foundation for all RPM-based OpenCharly boxes.

**Owned by the `opencharly/distro-fedora` submodule.** The Fedora base stack —
`fedora`, `/charly-distros:fedora-builder`, `/charly-distros:fedora-nonfree` — lives
bare-local in the **`opencharly/distro-fedora`** submodule (mounted at `box/fedora`),
which is SELF-CONTAINED (`import: []`): the base stack is bare-local and the
submodule composes the main repo's shared candies by `@github` git reference. Its
boxes write `base: fedora` and route builders to `fedora-builder` (bare-local
refs, no namespace qualifier). The Fedora consumer showcase boxes
(`/charly-coder:fedora-coder`, `/charly-distros:charly-fedora`, `/charly-distros:fedora-test`)
and the Fedora-rooted pod families all live in the same submodule, discovered as
`box/<name>/charly.yml` boxes. The main repo imports this submodule under the
`fedora` namespace (one-directional — fedora imports nothing back) to reference
those relocated boxes. Build with `charly box build fedora` from the submodule
(or `charly -C box/fedora box build fedora`).

## Box Properties

| Property | Value |
|----------|-------|
| Base | quay.io/fedora/fedora:43 |
| Layers | (none) |
| Platforms | linux/amd64 |
| Pkg | rpm |
| Registry | ghcr.io/opencharly |

## Quick Start

```bash
charly box build fedora
charly shell fedora
```

## dnf download tuning (`distro.fedora.dnf`)

The embedded `distro.fedora.dnf` vocabulary writes dnf download-speed knobs to
`/etc/dnf/dnf.conf` during the bootstrap, so they apply to the bootstrap install
AND every per-layer dnf install in this box and its descendants:

```yaml
# charly/charly.yml (embedded build vocabulary)
distro:
  fedora:
    dnf:
      max_parallel_downloads: 10   # concurrent package downloads
      fastestmirror: true          # sort mirrors by measured speed
```

These are **speed-only** — they never change which packages are selected
(`install_weak_deps` stays on the bootstrap `install_cmd`'s
`--setopt=install_weak_deps=False`). The block is a `DnfConfig` on `DistroDef`
and inherits across distro inheritance like the other sub-blocks. Source:
`charly/generate.go:renderDnfConfWrite`.

## Derived Boxes

- `/charly-distros:fedora-nonfree` — adds RPM Fusion repos
- `/charly-distros:fedora-builder` — adds pixi, nodejs, build-toolchain
- `/charly-distros:nvidia` — adds CUDA toolkit
- `/charly-openclaw:openclaw` — adds OpenClaw gateway
- `/charly-distros:githubrunner` — adds GitHub Actions runner

## Verification

After `charly box build`:
- `charly box list` — box appears in list
- `charly shell fedora` — interactive shell works

## Related Boxes
- `/charly-distros:fedora-nonfree` — adds RPM Fusion repos
- `/charly-distros:fedora-builder` — adds pixi, nodejs, build-toolchain
- `/charly-distros:charly-fedora` — full charly toolchain on Fedora
- `/charly-distros:arch` — pacman-based counterpart base

## Related Commands
- `/charly-build:build` — build the fedora base image
- `/charly-core:shell` — interactive shell in the base image

## When to Use This Skill

**MUST be invoked** when the task involves the fedora base image or understanding the box chain. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
