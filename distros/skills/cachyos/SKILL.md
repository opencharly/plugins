---
name: cachyos
description: |
  CachyOS base image (docker.io/cachyos/cachyos-v3) — x86_64_v3-optimized Arch
  derivative. Owned by the opencharly/distro-cachyos submodule (box/cachyos);
  consumed by main's versa box via the `cachyos` import namespace.
  MUST be invoked before building, deploying, or troubleshooting cachyos boxes.
---

# cachyos

CachyOS base image, pulled from the upstream-published OCI image
`docker.io/cachyos/cachyos-v3` (optimized for modern `x86_64_v3` CPUs), pinned
by digest in `box/cachyos/charly.yml` — Docker Hub publishes only a `:latest`
tag for `cachyos-v3`, so a digest is the most precise pin available.
CachyOS is an Arch derivative, so it shares the Arch toolchain, `pacman`, and the
`arch-builder` multi-stage builder.

The CachyOS family lives in the **`opencharly/distro-cachyos`** repo (git submodule at
**`box/cachyos`**), with the `cachyos` base image **owned there** and its
boxes discovered as `box/<name>/charly.yml`. It composes the main repo's shared
candies by `@github` git reference and imports the **`opencharly/distro-arch`** submodule
under the `arch` namespace (`import: [{arch: …}]`) so it reaches `arch.arch` (the
`cachyos-pacstrap-builder` base) and `arch.arch-builder` (the cachyos base's
builder) — one-directional, since arch imports nothing back. Build it
from the submodule: `charly -C box/cachyos box build cachyos` (or
`charly --repo opencharly/distro-cachyos box build cachyos`).

## Box Properties

| Property | Value |
|----------|-------|
| Base | docker.io/cachyos/cachyos-v3 (pinned by digest in charly.yml) |
| Layers | (none) |
| Platforms | linux/amd64 |
| Distro | cachyos, arch |
| Build | pac |
| Builders | pixi, npm, cargo, aur → arch-builder |
| Registry | ghcr.io/opencharly |
| Home repo | opencharly/distro-cachyos (`box/cachyos`) |

## main → cachyos coupling

The `cachyos` base and its derived boxes — `versa`, the `openclaw-*` family,
`githubrunner`, `android-emulator`, `charly-selftest`, and the `selkies-*` GPU
desktops — all live in the **`opencharly/distro-cachyos`** submodule, discovered as
`box/<name>/charly.yml` boxes. The main repo imports that submodule under the
`cachyos` import namespace to reference the relocated boxes from its own
`check`/`vm`/`local`/`k8s`/`android` entities:

```yaml
# main charly.yml
import:
  - cachyos: '@github.com/opencharly/distro-cachyos:<tag>'   # namespaced child import → cachyos.<entry>
```

This is a one-directional **main → cachyos** dependency. The submodule, in turn,
imports the **`opencharly/distro-arch`** submodule under the `arch` namespace (for
`arch.arch` and the `arch.arch-builder` builder) — also one-directional, since
arch imports nothing back. The whole import graph is therefore a DAG
(main → cachyos → arch, plus main → arch directly), with no mutual cycle. When a
repo is reached via two paths — arch, here, via main → arch and via
main → cachyos → arch — the loader resolves it to a single materialization **by
repo identity**, so main's namespace pins win and a stale transitive pin inside a
published submodule release never drags a divergent snapshot into the load (see
`/charly-internals:go` "import-namespace loader"). The image DAG
`versa → cachyos → docker.io/cachyos-v3` is itself acyclic. `versa` lives in the
same submodule as its `base: cachyos`, so it inherits the cachyos base's
`distro:`/`build:` values AND its `builder:` map (pixi/npm/cargo/aur →
`arch.arch-builder`) directly — there is no namespace boundary between them. The
namespace-relative builder map crosses the boundary once, where the cachyos base
itself names the qualified `arch.arch-builder` ref.

## AUR support — full parity with `arch`

CachyOS has the **same AUR capability as the `arch` base**, because it is
Arch-derived and its `builder.aur` points at the shared `arch-builder` (which
ships `yay`). Anything that builds on arch builds on cachyos:

- A box based on `cachyos` that needs AUR packages declares
  `build: [pac, aur]` (exactly as an `arch`-based box would — the base itself
  declares only `build: [pac]`, so the consumer opts in). The AUR builder stage
  (`<layer>-aur-build` via `arch-builder`) then compiles the packages and
  `pacman -U`-installs the `.pkg.tar.zst` artifacts. Worked example: the
  `selkies-desktop` box (`base: cachyos.cachyos`, `build: [pac, aur]`) builds
  `google-chrome` (chrome candy) + `wlrctl` (wl-tools candy) from the AUR.
- Candies author AUR packages under `distro.arch.aur.package` (see
  `/charly-image:layer` "AUR"); the `arch` distro tag is what cachyos boxes match
  (their `distro:` is `[cachyos, arch]`), so the same `distro.arch` sections used
  by every Arch box apply unchanged.
- The `cachyos` base declares `produce: [pixi, npm, cargo, aur]` (identical to
  `arch`), advertising the same builder-capability profile as every other base
  distro.

There is **no cachyos-specific AUR path** and no cachyos-only builder — AUR on
cachyos and AUR on arch are the same code path through `arch-builder`.

## Quick Start

```bash
charly -C box/cachyos box build cachyos
charly shell cachyos -c "pacman --version"
```

## Derived / sibling entries (all in opencharly/distro-cachyos)

- `/charly-distros:cachyos-pacstrap-builder` — privileged pacstrap builder (`base: arch.arch`)
- `/charly-distros:cachyos-pacstrap` — bootstrap-from-scratch rootfs (builds end-to-end)
- `/charly-vm:cachyos` — bootstrap VM (`cachyos-vm`) + `check-cachyos-vm` check bed
- `/charly-local:charly-cachyos` — the operator CachyOS workstation profile
- `/charly-versa:versa` — CachyOS-rooted notebook/OSM image in this submodule (`base: cachyos`)

### CachyOS GPU box family

The submodule also carries a CachyOS GPU box family — the Arch/CachyOS siblings
of the Fedora GPU boxes (which live in `box/fedora`). They build on the
`cachyos.nvidia` GPU base, which is `cachyos` + `agent-forwarding` + `nvidia` +
`cuda` (the `nvidia` and `cuda` candies are multi-distro — Fedora rpm + Arch pac —
so they compose unchanged on CachyOS):

- `cachyos.nvidia` — the GPU base (cachyos + agent-forwarding + nvidia + cuda)
- `cachyos.python-ml` — ML Python environment
- `cachyos.jupyter-ml` — CUDA ML JupyterLab
- `cachyos.ollama` — Ollama LLM server
- `cachyos.comfyui` — ComfyUI image generation
- `cachyos.unsloth-studio` — Unsloth Studio fine-tuning UI
- `cachyos.immich-ml` — Immich with the CUDA ML backend
- `cachyos.selkies-labwc-nvidia` — GPU NVENC Selkies streaming desktop (labwc flavor)
- `cachyos.selkies-kde-nvidia` — GPU NVENC Selkies streaming desktop (full KDE Plasma flavor)
- `cachyos.selkies-kde` — full KDE Plasma Selkies flavor on the plain cachyos base (VAAPI on an AMD/Intel render node, software x264 otherwise; the `-nvidia` sibling adds NVENC). The labwc cpu/amd flavor (`selkies-labwc`) lives in this same `box/cachyos` submodule.

## Why Docker Hub instead of pacstrap

The canonical base pulls the upstream OCI image (the path the CachyOS project
itself recommends — see https://github.com/CachyOS/docker). It's the faster
default (no privileged pacstrap, no kernel build). The pacstrap-from-scratch
variant (`/charly-distros:cachyos-pacstrap`) is retained for offline/air-gapped
builds and also builds end-to-end (the pacstrap renderer derives
`[options] Architecture` from the cachyos-v3 microarch repos and emits per-repo
`SigLevel`).

## Verification

After `charly -C box/cachyos box build cachyos`:
- `charly box list` — box appears
- `charly shell cachyos -c "pacman --version"` — pacman available
- `charly box inspect versa --format base` (from main) → `cachyos.cachyos` (the `cachyos` import namespace resolves)
- `charly check box cachyos` — build-scope check: 3 probes pass (os-release `ID=cachyos`,
  `pacman --version`, `pacman-conf --repo-list` contains `cachyos-v3`). These also
  pass when `cachyos` is built from main via the `cachyos` import namespace, and are
  inherited by `versa` through the base chain.

## When to Use This Skill

**MUST be invoked** when the task involves the cachyos base image, the
opencharly/distro-cachyos submodule, or the main → cachyos import-namespace coupling.
Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-distros:arch` — the Arch base (`cachyos-pacstrap-builder` is `base: arch.arch`, via the `arch` import namespace)
- `/charly-image:image` — box family umbrella (composition, build/validate/inspect)
- `/charly-internals:cutover-policy` — the hard-cutover policy governing submodule splits
