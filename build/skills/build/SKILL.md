---
name: build
description: |
  MUST be invoked before any work involving: building container images, charly box build command, pushing to registries, merging layers, build caches, or Containerfile generation.
---

# charly box build -- Building Container Images

Invoked as `charly box build`. See `/charly-image:image` for the family overview.

## Overview

`charly box build` generates Containerfiles from `charly.yml` and layer definitions, then builds images in dependency order using the configured build engine (Docker or Podman). Images at the same dependency level are built in parallel (up to `--jobs` concurrent builds).

**Mode purity**: `charly box build` reads `charly.yml` only. `charly.yml` is never read during build — this is enforced by `LoadConfig` in `charly/config.go`, which calls `LoadConfigRaw` (no `MergeDeployOverlay`) to guarantee OCI labels are baked strictly from authored configuration, never from local deploy-time overrides. See `/charly-internals:go` "Mode purity" for the architectural invariant this protects and the bug it prevents.

**Build-engine dispatch**: `charly box build` does NOT call `NewGenerator` inline — `BuildCmd.Run` computes the build tag, holds the build-activity retention lock, and dispatches through the COMPILED-IN `build:box` plugin (candy/plugin-build) over the F10 reverse channel; on return it runs the retention prune host-side. The plugin **OWNS the podman DRIVE** (the build-order loop, per-image build lock, `podman build`, push, and the inline-merge gate) IN the candy — it imports only the sdk module. It reaches the host for what a sdk-only candy cannot do: the loader + build PREP + the resolved-project ENVELOPE via `Executor.HostBuild("build-prep", …)` (which returns the envelope + a serializable drive-model — engine/platform, build order, per-image descriptors, resolved tunables; NO Containerfile content — the render DRIVE is `sdk/deploykit.Generator`, driven by the candy over the envelope + `HostBuild("render-seam")` for the host-coupled render seams, #67), and `HostBuild("bake-plugins")` for `bake_plugin:` binary baking. The host no longer renders the `.build/` tree (the render DRIVE moved to `sdk/deploykit` in #67); the host keeps ONLY the loader + build-prep + the resolve-project envelope projection. `charly box generate` mirrors this via `build:generate` → `HostBuild("build-prep")` with `GenerateOnly`: the candy renders the `.build/` tree itself via `deploykit.Generator` + returns the written Containerfile paths; no podman. See `/charly-internals:plugin` (the `build` provider class + the in-proc reverse channel) and `/charly-build:generate`.

**Build-mode emission**: the build-mode Containerfile render DRIVE is `sdk/deploykit.Generator.Generate` / `generateContainerfile` (relocated from `charly/generate.go` in #67), driven by `candy/plugin-build` over the resolved-project envelope + `HostBuild("render-seam")`; the `charly/generate.go` top-level `Generate`/`writeCandySteps` orchestrator is DELETED. `emitTasks` (`charly/tasks.go`) is a thin shim to `deploykit.Generator.EmitTasks` that STAYS for the pod-overlay deploy path (the candy `plugin-deploy-pod` constructs `deploykit.OCITarget` + renders via `deploykit.NewRenderGeneratorFromProject`, the per-step fragment over the `HostBuild("step-emit","oci-emit-step")` seam); the build-mode render (in `sdk/deploykit`) drives `WriteCandySteps` → `EmitTasks` directly. The render walks each layer's ops directly to write Containerfile text — NOT the `InstallPlan` IR. It shares the package-cascade / shell-snippet / localpkg compiler helpers with the IR (one source of truth, R3), but the overall walk is the direct generator. The `InstallPlan` IR + `deploykit.OCITarget.Emit` is the DEPLOY-mode path used by `charly bundle add` (the candy `plugin-deploy-pod`'s `add_candy:` overlay synthesis, rendered in its own code via `deploykit.OCITarget` + `deploykit.NewRenderGeneratorFromProject` + the external out-of-process deploys; the local/vm/k8s/android substrates are external plugins via `pluginDeployTarget` (S3b, dispatched through `candy/plugin-bundle`'s `Invoke(OpDeployDispatch)`) — `deploy:local` via candy/plugin-deploy-local and `deploy:vm` via candy/plugin-deploy-vm DO consume the IR (the plugin walks it via `kit.WalkPlans` over the reverse channel, the vm one over the guest `SSHExecutor`), while `deploy:k8s` via candy/plugin-kube does NOT, generating a Kustomize tree host-side). See `/charly-internals:install-plan` for the IR and `/charly-internals:generate-source` for the Go call graph.

**Three-phase templates**: the embedded build vocabulary's format and builder definitions split each install operation into `phases.{prepare, install, cleanup}.{container, host}` — three phases × two venues. Build-mode emission reads the `container` cell; local deploys read `host`. A top-level `install_template:` field serves as the `(install, container)` fallback when `phases:` is absent. See `/charly-image:layer` "Service Declaration" for the analogue at the init-system level (`init.<name>.service_schema`).

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Build all images | `charly box build` | Build all images in dependency order |
| Build specific image | `charly box build <image>` | Build single image for host platform |
| Build and push | `charly box build --push` | Build all platforms and push to registry |
| Build without cache | `charly box build --no-cache` | Disable build cache entirely |
| Merge layers | `charly box merge <image>` | Post-build layer optimization |

## charly box build Commands

```bash
charly box build [image...]                         # Build for local platform
charly box build --push [image...]                  # Build for all platforms and push
charly box build --platform linux/amd64 [image...]  # Specific platform
charly box build --cache registry [image...]         # Registry cache (read+write)
charly box build --cache image [image...]           # Image cache (read-only, default)
charly box build --cache gha [image...]             # GitHub Actions cache
charly box build --no-cache [image...]              # Disable cache entirely
charly box build --jobs N [image...]                # Max concurrent images per DAG level (0=auto from defaults.jobs, else 4)
charly box build --podman-jobs N [image...]         # Max concurrent stages within a single podman build (0=auto: min(NCPU, defaults.podman_jobs_cap))
charly box build <image> --include-disabled         # Build an `enabled: false` image without flipping authored config
charly box build <image> --dev-local-pkg            # EVAL-BED ONLY: build localpkg candies (the charly toolchain) from LOCAL in-dev source, not the published release
```

### `--dev-local-pkg` — disposable check beds bake the IN-DEVELOPMENT charly

A `localpkg:` candy (the `charly` toolchain) normally installs the latest
**published** release in an image build (`releases/latest/download/`). The
check-bed runner instead passes `--dev-local-pkg` for EVERY bed image build, so the
package is BUILT from the LOCAL working tree (`pkg/<fmt>` + `charly/`) — a
disposable check bed always tests the in-development charly, never a stale release.
Generic across all kinds + all localpkg candies, one decision point
(`deploykit.RenderLocalPkgImageInstall`); a production box build omits the flag. A dev build
that cannot find its local source HARD-errors (no silent release fallback, R4).
Full mechanics: `/charly-internals:install-plan` "Check-vs-production charly
toolchain"; the candy view: `/charly-tools:charly`.

## `--include-disabled` — operational rebuild of disabled images

Images with `enabled: false` in `charly.yml` are excluded from the build /
inspect / validate working set by default. To rebuild ONE such image without
flipping the authored flag (which would commit local-deployment intent into
shared project config), pass `--include-disabled`:

```bash
charly box build immich --include-disabled    # builds the disabled image
git diff --quiet charly.yml                  # confirms charly.yml is untouched
```

**Scoping.** When you pass positional `<image>` args together with
`--include-disabled`, the override is **scoped to those names**. Other
disabled images stay filtered out — important because widening the
working set globally would surface unrelated dep errors (e.g., a
disabled image with remote layers that haven't been fetched yet).
`charly box build --include-disabled` (no positional args) widens
globally; `charly box build immich --include-disabled` only relaxes the
gate for `immich`.

The flag flows from `BuildCmd.IncludeDisabled` → `ResolveOpts.IncludeDisabled`
+ `ResolveOpts.IncludeDisabledNames` → `ResolveAllBox` (a `*Config` method)
→ `ResolveBox`. The `shouldIncludeDisabled(name)` helper centralises the
scoping rule. Sibling commands `charly box inspect <name> --include-disabled`
and `charly box validate --include-disabled` accept the same flag for
diagnostic / validation work on disabled entries. See `/charly-build:inspect`
and `/charly-build:validate`.

## Build Config (the embedded build vocabulary)

Containerfile generation is driven by the build vocabulary (`distro:` / `builder:` / `init:` /
`resource:`). The DEFAULT vocabulary is EMBEDDED in the `charly` binary (`charly/charly.yml`,
`//go:embed` — the single embedded default config, plain node-form YAML parsed by the
same unified loader as any project `charly.yml`) and
merged as the lowest-priority base — a project needs
no build vocabulary of its own. A project EXTENDS or OVERRIDES it by declaring its own
`distro:`/`builder:`/`init:`/`resource:` entries inline in `charly.yml` or in an imported
vocabulary file (project-wins; the former `defaults.format_config:` field is gone).

The embedded `charly/charly.yml`'s build vocabulary has three top-level sections:

- **`distro:`** — Per-distro bootstrap commands (package manager setup, cache mounts, repo management), optional `base_user:` declaration (what uid-1000 account the upstream base image ships), and package format templates (how `rpm:`, `pac:`, `deb:` sections in charly.yml become `RUN` steps). Each format has `install`, `repos`, `copr`, `modules`, and `options` templates.
- **`builder:`** — Multi-stage builder patterns (pixi, npm, cargo, aur). Each builder has `build_stage` and `copy_stage` templates that generate the appropriate `FROM builder AS ...` and `COPY --from=...` steps.
- **`init:`** — Init system definitions (supervisord, systemd) including detection rules, fragment templates, entrypoint commands, and service management commands. Optional — images can omit this if they don't need an init system.
- **`resource:`** — Exclusive host-resource vocabulary: maps an arbitration token (the name used by a deploy/bed's `requires_exclusive:` and a holder's `preemptible.holds:`) to an optional hardware selector. A `gpu:` selector (`resource: {nvidia-gpu: {gpu: {vendor: "0x10de"}}}`) lets `charly vm create` AUTO-ALLOCATE the matching PCI `<hostdev>` for a GPU-requiring VM (detect → persist into the per-host `instance.yml` → inject) — or FAIL HARD when no matching card is present. The selector lives in YAML, never hardcoded in Go: adding a resource is a config edit. Optional + additive (configs without it load unchanged). See `/charly-internals:disposable` "resource-arbitration axis", `/charly-vm:vm` "GPU passthrough", `/charly-core:deploy` `requires_exclusive`.

All sections use Go `text/template` syntax with access to layer config data. Source: `charly/format_config.go` (loader + distro/builder types, including `DistroDef.BaseUser`), `charly/init_config.go` (init type), `charly/format_template.go` (rendering).

### `base_user:` — declaring a pre-existing base-image account

`base_user:` handles upstream base images that ship a pre-existing uid-1000 account (e.g. Ubuntu 24.04's `ubuntu:ubuntu`). Declare it under the distro when the upstream base image ships a uid-1000 account; leave it out otherwise.

```yaml
distro:
  ubuntu:
    inherits: debian
    base_user:
      name: ubuntu
      uid: 1000
      gid: 1000
      home: /home/ubuntu
    # ... bootstrap inherited from debian
```

All four fields (`name`, `uid`, `gid`, `home`) are required when the block is present. Inherited across distro inheritance chains — if the child has no `base_user:` but the parent does, the child inherits it (see `resolveInherits` in `charly/format_config.go`).

Consumed by the `user_policy:` reconciliation in `charly/config.go:ResolveBox` — see `/charly-image:image` "user_policy" for the three-value policy (`auto` / `adopt` / `create`) and the decision matrix.

No `base_user:` currently declared for Fedora, Arch, or Debian (their canonical base images ship no pre-existing uid-1000 account). Add one in your project's `charly.yml` build-vocabulary override if you're basing on a distro-cloud variant that DOES ship one (e.g. `debian:13-cloud`).

### `version:` — the canonical distro version (for VM per-version reach)

Each distro may declare a canonical `version:` (`distro.debian.version: "13"`, `distro.ubuntu.version: "24.04"`, `distro.fedora.version: "43"`; arch/cachyos are rolling and omit it). It is the single source for synthesizing the most-specific-first tag chain `[<distro>:<version>, <distro>]` on a target that carries only a bare distro name — a `target: vm` deploy, where no image-authored `distro:` tag supplies the version. `syntheticVmBox` + the `distroTagChain` helper consume it so a VM deploy of an ubuntu guest reaches per-version `distro:` sections (e.g. `ubuntu-24.04`) exactly like an image build does. Inherited child-wins via `resolveInherits` (cachyos inherits arch → stays version-less). Image builds carry the version in their own `charly.yml` `distro:` tags and don't need it. See `/charly-image:layer` "Package Surface" and `/charly-internals:install-plan`.

### The `builder:` name in two places

`builder:` appears in both the embedded build vocabulary (top-level section) and `charly.yml` (per-image map, plus `defaults.builder`). They share the name on purpose — both maps key on the same slot (the build-type name, e.g. `pixi`, `npm`, `cargo`, `aur`):

- the embedded build vocabulary's `builder.pixi` — **definition**: detection rules, stage template, cache mounts for the pixi builder.
- `charly.yml` `builder.pixi` — **selection**: which image (e.g. `fedora-builder`) to use as the pixi builder for this image.

An image's effective builder map resolves as: `box.builder[type]` → `base_box.builder[type]` → `defaults.builder[type]` → `""`. Self-references (a builder image pointing at itself) are filtered automatically.

### Why one file, not three

The embedded build vocabulary was unified from three former files (`distro.yml` + `builder.yml` + `init.yml`) because they were always resolved together through the same `format_config:` ref. One file → one loader (`LoadBuildConfigForBox`) → three in-memory configs (`DistroConfig` / `BuilderConfig` / `InitConfig`) — the internal split is preserved, only the YAML surface is unified. The `init:` section is optional (absent = no init system); `distro:` and `builder:` are required.

## Containerfile Generation

`charly box build` runs `charly box generate` internally. You can also run it standalone to inspect generated Containerfiles:

```bash
charly box generate                          # Write .build/ (Containerfiles)
charly box generate --tag v1.0.0             # Override CalVer tag
cat .build/my-image/Containerfile    # Inspect generated output
```

## Build Flow

1. Run `charly box generate` internally (produces Containerfiles in `.build/`)
2. Resolve runtime config to get build engine (`engine.build`)
3. Resolve image build order (dependency ordering, grouped by level)
4. Filter to requested images (and their base dependencies)
5. For each level: build images in parallel (up to `--jobs` concurrent, default 4)
6. After all builds: `charly box merge --all` (if `merge.auto` enabled, skipped for `--push`)

## Parallelism: `--jobs` vs `--podman-jobs`

charly exposes **two** parallelism knobs with distinct meanings:

| Flag | Env var | `defaults:` key | What it controls |
|---|---|---|---|
| `--jobs N` | `CHARLY_BUILD_JOBS` | `jobs` | **Outer** concurrency: how many charly-level images to build in parallel within a DAG level (e.g., when `charly box build` rebuilds the whole graph). |
| `--podman-jobs N` | `CHARLY_PODMAN_JOBS` | `podman_jobs` (+ `podman_jobs_cap`) | **Inner** concurrency: passed to `podman build --jobs N`, controls how many stages of a *single* multi-stage build run concurrently. |

Both knobs are **config-driven**: precedence is **CLI flag → env → `defaults:`
in `charly.yml` → built-in fallback** (4). The inner auto value (when
`--podman-jobs` / `CHARLY_PODMAN_JOBS` / `defaults.podman_jobs` are all unset) is
CPU-proportional, capped at `defaults.podman_jobs_cap`: `min(NCPU, cap)`. The
cap is the operative ceiling; the repo ships `podman_jobs_cap: 8`. (A
high-concurrency `--cache-from` SIGABRT race in podman ≤ 5.7.x originally
motivated a hard cap of 4 — see `CHANGELOG/` for that history and the 20-run
race gate required before raising the cap on a new podman version.)

```yaml
# charly.yml — defaults: block
defaults:
  jobs: 4              # outer: images per DAG level
  podman_jobs: 0       # inner: 0 = auto = min(NCPU, podman_jobs_cap)
  podman_jobs_cap: 8   # ceiling for the auto calc
```

```bash
charly box build <image> --podman-jobs 16             # fully parallel stages (override)
CHARLY_PODMAN_JOBS=8 charly update <image> --build    # via env
charly box build <image> --podman-jobs 1              # fully serialised, worst-case debugging
```

Source: `charly/build.go:resolvePodmanJobs(override, cap)` + `podmanJobsCapFallback`
/ `jobsFallback`; config fill in `BuildCmd.Run`. Covered by
`charly/build_jobs_test.go`. The outer `--jobs` knob and the inner `--podman-jobs`
are separate fields so the two semantics don't get conflated.

## Build-context excludes (`defaults.context_ignore`)

`charly box generate` writes BOTH `.containerignore` and `.dockerignore` at the
project root from a single source: a built-in baseline (`.git`, `bin`, `charly`,
`*.md`, plus editor/python/node cache-bust globs) **plus** every entry in
`defaults.context_ignore`. Both files are generated artifacts (gitignored) — do
not hand-edit them; add excludes to `defaults.context_ignore` instead.

```yaml
# charly.yml — defaults: block
defaults:
  context_ignore:        # heavy dirs never COPYed by any Containerfile
    - image
    - .check
    - output
    - pkg
    - tests
```

Why it matters: the build context tar is streamed to the engine on **every**
build regardless of cache state, so excluding large never-COPYed directories is
the dominant warm-rebuild win. podman reads `.containerignore`; docker reads
`.dockerignore` — emitting both keeps the two engines in lockstep. Only add a
directory you've confirmed no Containerfile COPY/ADDs from (generated
Containerfiles COPY only from `candy/`, `templates/`, `.build/`). Source:
`charly/generate.go:writeContextIgnore` + `baselineContextIgnore`.

## Image-tag retention (`defaults.keep_images`)

After `charly box build` (push runs excluded), charly prunes old CalVer tags per image
down to `defaults.keep_images` — keeping the newest N builds per
`ai.opencharly.box` group, ordered by the `ai.opencharly.version` label
(the content-derived EffectiveVersion) as the PRIMARY key, with the `:YYYY.DDD.HHMM`
build TAG as the tiebreaker. The tag tiebreak is load-bearing: the label is
content-stable, so many builds of an unchanged image share one label-CalVer and
the tag is what distinguishes (and retains) the newest BUILDS. Images referenced
by a container (`podman ps -a`) are skipped, and `rmi` runs without `-f` as a
backstop, so a running deploy's image is never removed.

```yaml
# charly.yml — defaults:
defaults:
  keep_images: 3   # newest CalVer tags to keep per image; 0 (or absent) disables
```

This stops the iterative-build tag accumulation that otherwise reclaims
nothing. Run it on demand (and clear a backlog) with `charly clean` — see
`/charly-core:clean` for the full retention surface (images + check runs + makepkg).

## Build Cache

| Mode | Backend | Use Case |
|------|---------|----------|
| `image` | `<registry>/<image>` | Read-only cache from registry image (default) |
| `registry` | `<registry>/cache:<image>` | Production CI/CD (read + write) |
| `gha` | GitHub Actions cache | CI builds on GitHub Actions |
| `none` | No cache | Same as `--no-cache` |

```bash
charly box build --cache registry my-image        # Read+write registry cache
charly box build --cache image my-image          # Read-only from registry image
CHARLY_BUILD_CACHE=registry charly box build         # Via environment variable
```

The default cache mode is also config-driven: precedence is `--cache` →
`CHARLY_BUILD_CACHE` → `defaults.cache` in `charly.yml` → auto (`image` for local
builds, `registry` for `--push`). Set `defaults.cache: image` to make the
read-only registry cache the project default without per-invocation flags.

## CalVer-only tagging (no `:latest`)

`charly box build` tags every image with exactly one tag — its CalVer
(e.g. `ghcr.io/opencharly/fedora-supervisord:2026.114.1022`). charly does
**not** emit a `:latest` tag, ever. Short-name resolution (in
`sdk/kit/local_image.go`, `kit.ResolveLocalImageRef` — moved from
`charly/local_image.go` in P12a) picks the newest CalVer for a given short name
via the `ai.opencharly.box=<short>` + `ai.opencharly.version=<calver>`
OCI labels. The CLI accepts an explicit `--tag <calver>` for pinning;
an empty `--tag` resolves to newest-local automatically.

Rationale:
1. **No stale-`:latest`-under-`--cache-from` bug.** The documented
   caveat where podman's `--cache-from` silently pulls a stale
   `:latest` from the remote registry is unreachable when charly never
   emits `:latest` in the first place.
2. **No "ambiguous short name" errors under multiple tags.** Previously
   the resolver listed every `:latest` + `:<calver>` tag of the same
   image as competing candidates; the CalVer sort picks the newest
   one deterministically.
3. **One-tag-per-build keeps registry + local storage lean.** A float
   tag is a permanent nameable handle you have to garbage-collect;
   a CalVer tag is self-describing and rotates naturally.

Any stray `:latest` tag in local storage is never refreshed by a new
build; prune it with `podman image prune` if you want it gone.

## Cache Efficiency

### Core invariant — cache hits fully when nothing has changed

**Running `charly box build <image>` with no source changes completes in seconds — every RUN/COPY/LABEL step hits the cache.** This is the invariant the rest of this section builds on. Cache-miss only happens when something in the build input genuinely changes; a rebuild you triggered "just to be sure" is free.

Concretely: the cache is keyed by `(parent-image-SHA, instruction-text, COPY-source-content)`. The parent-image SHA resolves from the FROM reference at build time — a fresh CalVer tag that still points at the same image SHA keeps the subsequent RUN/COPY steps cached. Only when the underlying image SHA changes (because that upstream was rebuilt with changed content) does cache-miss cascade to the downstream steps.

### What legitimately invalidates cache

Three kinds of source changes are real cache invalidators — if you see a long rebuild, one of these is the cause:

1. **Layer source file content changed.** Editing a file under `candy/<name>/` — the canonical case is `candy/charly/bin/charly` being rewritten by `task build:binary` after a Go source edit — changes the scratch stage's content hash, which invalidates `COPY --from=<layer>` and everything downstream that depends on it.
2. **Package list / task text changed.** Adding/removing an rpm/deb/pac entry or editing a `command:` body changes the RUN instruction text emitted for that layer, invalidating cache from that RUN onward.
3. **Upstream image content changed.** If a base image (external like `fedora` or internal like `fedora-supervisord`) has different content from the last cached build, the FROM step resolves to a new SHA and downstream RUN/COPY steps all cache-miss. This cascades through the dependency graph — rebuilding `fedora-supervisord` forces its children to re-run from the `FROM fedora-supervisord` step.

### What does NOT invalidate cache

- **CalVer tag shifts alone.** The Containerfile emits `ARG BASE_IMAGE=<registry>/<name>:<calver>` with a fresh CalVer on every generate. That ARG default appears in the Containerfile text but is not part of the cache key for subsequent RUN/COPY steps — podman/buildah resolves the FROM to an image SHA first, and caches downstream steps off that SHA. If the SHA is unchanged, cache hits. The cache cost comes from content changes in the layer itself, not the tag.
- **Baked `plan:` edits.** LABEL directives are emitted last in every final stage (after the last USER). Editing a baked step (a `check:`/`agent-check:` step, or a runtime-context `run:` step) — a common layer mutation — only re-runs the final LABEL block (~2 seconds on a 138-step stack like `immich-ml`). (Editing a build/deploy-context `run:` step changes the install timeline, so it re-runs that RUN/COPY instead.) See `/charly-internals:generate-source` for the rationale.
- **Re-running `charly box build` without source changes.** Fully cached; seconds to complete.

### `write:` vs `copy:` — cache granularity

- `write:` steps use `stageInlineContent` (content-addressed staging under `.build/<image>/_inline/<layer>/<sha256>/`). Editing a `write: content:` block changes only that single COPY layer's cache key — siblings in the same layer keep their cache.
- `copy:` steps reference files from the layer directory. Editing any file under `candy/<name>/` changes the WHOLE scratch stage's content hash (since `COPY candy/<name>/ /` is one instruction), invalidating every downstream `COPY --from=<layer>` step.

### Rule of thumb for rebuild cost

| Edit | Cost |
|------|------|
| `charly box build` with zero source changes | Seconds — every step cache-hits |
| A baked `check:` step / label entry | ~2 sec (LABEL re-emit only) |
| A `write:` step's content | Just that single content-addressed COPY layer |
| A `copy:` source file's content | Rebuild from that layer's COPY onward + downstream |
| A `command:` / `download:` run step body | Rebuild from that RUN onward + downstream |
| A package added/removed in `rpm:`/`deb:`/`pac:` | Rebuild from the install RUN onward + downstream |
| `task build:binary` → new `candy/charly/bin/charly` | Rebuild the `charly` layer + every image that includes it |
| An upstream image got content-changed and rebuilt | Rebuild from the FROM step onward in every descendant |

## Build Flow Details

**Internal base images** use exact CalVer tags in Containerfiles (`FROM ghcr.io/opencharly/fedora:2026.46.1415`). This ensures each image references the precise version of its parent. Both Docker and Podman resolve local images before pulling from registry.

## Push Mode

- **Docker:** `docker buildx build --push` for multi-platform builds
- **Podman:** `podman build --manifest` + `podman manifest push`

Podman manifest push uses retry with exponential backoff (3 attempts, 5s/10s/20s delays) to handle transient registry errors (e.g., GHCR 500 errors after long builds).

Source: `charly/build.go` (`retryCmd`).

## Layer Merging

Post-build optimization that merges consecutive small layers:

```bash
charly box merge <image> --dry-run         # Preview what would be merged
charly box merge <image>                   # Merge small layers
charly box merge --all                     # Merge all images with merge.auto enabled
charly box merge <image> --max-mb 512      # Custom per-layer threshold
charly box merge <image> --max-total-mb 4096  # Custom total image size limit
```

Configure in charly.yml:

```yaml
defaults:
  merge:
    auto: true        # Auto-merge after builds
    max_mb: 128       # Max merged layer size (MB)
    max_total_mb: 0   # Max total image size for merge (0 = no limit)
```

CLI flags `--max-mb` and `--max-total-mb` override `charly.yml`. `auto` is only used by `charly box merge --all` to select which images to merge; `charly box merge <image>` always merges regardless. `max_total_mb` controls whether large images skip merging entirely (the merge process decompresses layers in memory). Set to `0` to disable (default), or a positive value like `2048` to cap on low-memory CI runners.

### Algorithm

1. Load image from engine via `<engine> save` -> `tarball.ImageFromPath()`
2. Get compressed sizes via `layer.Size()`
3. Group consecutive layers into groups totaling <= `max_mb`
4. Single-layer "groups" are kept as-is (need 2+ layers to merge)
5. For each merge group: read uncompressed tarballs, deduplicate entries by path (last writer wins), write combined tar into a single new layer
6. Reconstruct image with `mutate.Append()`, preserving OCI history alignment (empty-layer entries for ENV/USER/EXPOSE kept in correct positions)
7. Save via `tarball.WriteToFile()` -> `<engine> load`

Merge is idempotent -- running again after merging shows all layers as `[keep]`. The engine itself lives out-of-process in `candy/plugin-oci/merge.go` (`runMerge`/`mergeImageRef`, the P14a cutover); `charly box merge`'s CLI surface is `candy/plugin-box/merge_cmd.go` (P14 — relocated OUT of charly core, which now carries zero merge-specific code).

### Inline Merge

Images are merged immediately after building, before their children are built. Child images inherit a merged (fewer-layer) base, producing smaller final images. Both local and push builds merge inline. `candy/plugin-build/drive.go`'s `mergeBox` handles this -- it checks `MergeAuto` on the build-resolve model and asks `verb:oci` to run the merge via `InvokeProvider` if enabled.

For filtered builds (`charly box build <image>`), only the built images are merged. For full builds (`charly box build`), merge runs after each dependency level completes.

## Engine Configuration

```bash
charly settings set engine.build docker   # or podman
charly settings set engine.run docker     # or podman
```

## Host Bootstrap (First Time)

Requires: `go-task`, `go`, `docker` (or `podman`). There is no host-installing build task — `task build:binary` produces ONLY a per-checkout `bin/charly` (no install step); getting `charly` onto `$PATH` is always an explicit follow-up step you choose.

```bash
task build:binary        # Build ./bin/charly (CalVer-stamped; no install)
task install-portable    # Optional: copy it to $HOME/.local/bin/charly, onto $PATH
task setup:builder       # Create multi-platform buildx builder
./bin/charly box build   # Generate + build + merge all images (drop `./bin/` once installed)
```

For a distro-native package instead (system-wide, via your OWN package manager — never via a Taskfile install step): `task pkg:arch`/`pkg:fedora`/`pkg:debian` builds a `.pkg.tar.zst`/`.rpm`/`.deb` into `dist/`, which you install yourself (`pacman -U dist/*.pkg.tar.zst` / `dnf install dist/*.rpm` / `apt install dist/*.deb`).

## Common Workflows

### Build a Single Image

```bash
charly box build my-app
```

### Rebuild After Layer Changes

```bash
charly box build my-app
# Only changed layers are rebuilt (Docker layer cache)
```

### Push to Registry

```bash
# Authenticate first
docker login ghcr.io
# or: podman login ghcr.io

charly box build --push
```

## Troubleshooting

### "charly not found"

Build a distro-native package (`task pkg:arch`/`pkg:fedora`/`pkg:debian` into `dist/`) and install it with your OWN package manager (`pacman -U`/`dnf install`/`apt install`), or run `task install-portable` for a `$HOME/.local/bin/charly` copy — `task` itself is required (install via your distro package manager or download from go-task/task releases).

### Build Fails with Missing Base

Build base images first. `charly box build` handles dependency ordering automatically, but if building a single image, its base must already exist.

### Cache Miss

First build on a new machine won't have cache. Use `--cache registry` to pull from registry cache if available.

### RPM Conflict: ffmpeg-free vs negativo17

If a build fails with `conflicting requests` involving `libavcodec-free` vs `libavcodec` (epoch 1), the candy is trying to install `ffmpeg-free` (Fedora) in an image that has negativo17's `ffmpeg-libs` (via cuda candy). Fix: change `ffmpeg-free` to `ffmpeg` in the candy's `rpm.packages` and add the `fedora-multimedia` repo from negativo17. See the `immich` candy for the correct pattern.

### YAML Unmarshal Error on charly.yml

If you see `cannot unmarshal !!str ... into int` or similar YAML parsing errors on layer fields, the installed `charly` binary is likely stale. Rebuild with `task build:binary` and `cp bin/charly ~/.local/bin/charly` (or re-run `task install-portable`). Verify with `charly box validate`.

### Stale `charly` binary produces stale Containerfiles

Beyond the YAML-unmarshal symptom above, a stale `charly` binary can produce *syntactically valid but outdated* Containerfile output — e.g. emitting an old broken form of a template that HEAD's source has already fixed. Symptom: build fails on a step whose generated shell clearly doesn't match the source you see in `git grep`. Quick diagnostic: `ls -la $(which charly)` vs. `git log -1 charly/generate.go` — if the binary predates the fix, rebuild:

```bash
task build:binary && task install-portable   # rebuild + refresh the $HOME/.local/bin copy
# or: task pkg:arch && pacman -U dist/*.pkg.tar.zst   # rebuild + reinstall the native package
```

If you find yourself rebuilding `charly` to chase a bug and the symptom persists, the binary path on $PATH may not be the one you just refreshed — confirm with `which charly`, and remember a worktree's own `./bin/charly` is a THIRD candidate the freshness guard tracks separately (see `/charly-internals:agents` "The charly binary in a multi-teammate / multi-worktree setup").

### Buildah cache-mount corruption (pixi tzdata et al.)

Cache mounts declared via `--mount=type=cache,dst=<path>,uid=<u>,gid=<g>` (used for pixi, npm, cargo, rattler, dnf) persist across builds and are **not** evicted by `charly box build --no-cache` (which only suppresses `--cache-from`; see above). A disk-full event mid-download can leave a partial package in the cache, and every subsequent build re-hits the same broken file:

```
error: × failed to link tzdata-2025c-hc9c84f9_1.conda
  ├─▶ failed to copy file ... zoneinfo/<Region>/<City>: No such file or directory
```

Options, in order of least to most disruptive:

1. **Just retry the build.** Often the cache clears itself once the partial package finishes downloading or gets superseded by a checksum mismatch.
2. **Bump a content-hash on the builder layer** (e.g. `echo "" >> candy/pixi/charly.yml`) to evict the cache mount associated with that build-stage's hash, then revert the cosmetic change. Same workaround as the scratch-stage cache issue above.
3. **`podman image prune -af` is NOT the right hammer** — see next note.

### `podman image prune -af` caveat — removes tagged-but-idle images

`podman image prune -a -f` will delete tagged images that are **not referenced by a running container**. That means the image you just built via `charly box build` — and haven't started as a container yet — is eligible for prune. Observed sequence: `charly box build` → `podman image prune -af` → `sudo podman load` (manual rootful refresh) fails with `image not known`. Protect the fresh build by starting a container or use `prune` with explicit filters instead.

### `--no-cache` does not invalidate intermediate scratch-stage caches

`charly box build --no-cache <image>` and `charly box build --cache none <image>` reliably disable the
cache for the **final image stage**, but in observed behavior they do **not** propagate
to intermediate scratch stages produced by `COPY candy/<x>/ /` instructions
(`[15/25] STEP 2/2: COPY candy/labwc/ /` style). Editing a single file inside a layer
directory and rebuilding with `--no-cache` may still pull the labwc scratch stage from
cache, leaving the new file content out of the rebuilt image.

**Workaround:** force a content-hash bump on the layer's `charly.yml`. The simplest is
adding (or removing) a trailing comment line:

```bash
echo "" >> candy/labwc/charly.yml          # bump content hash
charly box build selkies-desktop                   # now invalidates the labwc scratch stage
git checkout -- candy/labwc/charly.yml     # revert the cosmetic change
```

This was discovered while shipping commit `febb9bd` (labwc autostart race fix): the
edit to `candy/labwc/autostart` did not propagate to the rebuilt image until
`candy/labwc/charly.yml` itself was touched. Two consecutive `--no-cache` rebuilds
produced the same image hash (`502c8012c7a5`) until the charly.yml content changed.

Symptom: `charly box list tags <name>` shows a new tag, but `charly shell <image> -c "cat /path/to/changed/file"`
returns the **old** content.

### Known caveat: stale `:latest` under `--cache-from`

charly's Containerfile generator currently emits `FROM <registry>/<builder>:latest`
for parent builder images (not pinned CalVer). When charly invokes
`podman build --cache-from <registry>/<image>`, podman resolves those `FROM`
clauses at parse time and will **pull `:latest` from the remote registry**,
silently clobbering any locally-rebuilt `:latest` tag. For images that rebuild
their builder stages in the same invocation this can lead to the later
stages using the **stale registry builder** instead of the freshly-built one.

**Symptom observed on this project:** `charly update selkies-desktop --build`
fails deep inside selkies' `pixi install && bash build.sh` step with
`error: can't find Rust compiler`. The remote
`ghcr.io/opencharly/fedora-builder:latest` predates the `build-toolchain`
layer adding `cargo` as an RPM, so its pixi env has no rustc — even though
the current local `build-toolchain/charly.yml` lists `cargo`. The build phase
that rebuilds fedora-builder locally *does* run, but parent-stage FROM
resolution happens before that stage exists, and podman pulls the stale
remote image.

**Workaround until the generator is fixed:**

```bash
charly box build <image> --cache=none      # or equivalently --no-cache at the charly level
```

Both `--cache=none` and `--no-cache` short-circuit `cacheArgs()` in
`charly/build.go:cacheArgs` and do NOT pass `--cache-from` to podman, so
the broken resolution path never fires. `--no-cache` is charly-level only — it
does *not* pass `--no-cache` to podman, it just skips `--cache-from`.

**Proper fix (not yet implemented):** charly's generator should emit pinned
CalVer tags for builder `FROM` clauses (e.g.,
`FROM ghcr.io/opencharly/fedora-builder:2026.105.0128`) or pass
`--pull=never` to podman so local tags aren't resolved from the remote.
Tracked as a follow-up.

See also: `/charly-build:generate` for the Containerfile generation path, `/charly-core:charly-update`
for the `--build` flag that also picks up this caveat.

## Project directory override

`charly box build` (like every build-mode command) resolves `charly.yml` via `os.Getwd()`. Override with `-C <dir>` / `--dir <dir>` / `CHARLY_PROJECT_DIR=<dir>` — honoured before Kong dispatch. See `/charly-image:image` "Project directory resolution" for the canonical reference and the `charly mcp serve` use case. Typical use: building from an `charly mcp serve` MCP tool where the container cwd doesn't hold the project.

## Cross-References

### `charly box` family siblings

- `/charly-image:image` -- Family overview + charly.yml composition reference
- `/charly-build:generate` -- Containerfile generation (called internally; stale `:latest` FROM lives there)
- `/charly-build:inspect` -- Inspect resolved image config before building
- `/charly-build:list` -- Enumerate images, layers, build targets
- `/charly-build:merge` -- Post-build layer consolidation (runs inline after each build level)
- `/charly-build:new` -- Scaffold a new candy directory before adding to `charly.yml`
- `/charly-build:pull` -- Pull prebuilt images; orthogonal to building (use for downstream deploy-mode commands)
- `/charly-build:validate` -- Validate `charly.yml` + layers before building

### Related skills

- `/charly-image:layer` -- Layer definitions that get built
- `/charly-check:check` -- Tests are embedded as `ai.opencharly.description` OCI label at build time; LABEL-at-end optimization (see Cache Efficiency above) makes test edits cheap.
- `/charly-core:charly-update` -- `charly update <image> --build` invokes `BuildCmd.Run` and picks up the same `--jobs` cap and stale-`:latest` caveat
- `/charly-vm:vm` -- Building bootc disk images (`charly vm build`)
- `/charly-core:charly-config` -- Engine configuration
- `/charly-automation:enc` -- Encrypted-volume restart path interacts with the `--build` flow (`charly config mount` short-circuit means builds can restart services without touching the keyring)

## When to Use This Skill

**MUST be invoked** when the task involves building images, pushing to registries, build caches, or layer merging. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Typically first in a lifecycle chain.
Next step: `/charly-core:deploy` (quadlet setup, tunnels) → `/charly-core:service` (start and manage).

## Related skills

- `/charly-internals:capabilities` — OCI labels emitted during the build stage; `CapabilityLabelMap` completeness check

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM in vm.yml.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See the project rulebook R1–R10 (`AGENTS.md` / `CLAUDE.md`).
