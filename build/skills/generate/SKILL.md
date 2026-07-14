---
name: generate
description: |
  Containerfile generation from charly.yml and layers.
  MUST be invoked before any work involving: charly box generate command, Containerfile generation, .build/ directory contents, the task-verb emission pipeline, or understanding generated output.
---

# charly box generate -- Containerfile Generation

Invoked as `charly box generate`. See `/charly-image:image` for the family overview.

## Overview

Parses `charly.yml`, scans `candy/`, resolves the dependency graph, and emits all build artifacts into the `.build/` directory. Called internally by `charly box build` but can be run standalone to inspect generated output before a build.

The generator is **config-driven** — distro format templates, builder stage templates, and init system fragments all come from the build vocabulary embedded in the `charly` binary at `charly/charly.yml` (three top-level sections: `distro:`, `builder:`, `init:`) — and **declarative per-task** for install logic — each task verb (see `/charly-image:layer`) has a dedicated emitter that writes the right Containerfile directive.

**Build-engine dispatch**: `charly box generate` does NOT call `NewGenerator` inline — it is served by the COMPILED-IN `command:box` plugin (candy/plugin-box, nested under the `box` grammar group), whose generate handler invokes the peer `build:generate` plugin (candy/plugin-build) over the F10 reverse channel (InvokeProvider). The plugin calls `Executor.HostBuild("build-resolve", …)` with `GenerateOnly` set; the host runs the loader RESOLVE + the Containerfile RENDER HOST-SIDE (a sdk-only candy cannot run the loader) and returns the written Containerfile paths in `spec.BuildResolveReply.Written` — no podman, no merge (generate builds nothing). The RESOLVE/RENDER (`NewGenerator` / `Generate` / the runtime Candy graph) STAYS host-side, reached via the seam. `charly box build` uses the SAME `build:generate` seam, then the candy additionally OWNS the podman DRIVE (`podman build` / push / inline-merge via `HostBuild("merge")`) IN the candy. See `/charly-internals:plugin` (the `build` provider class + the in-proc reverse channel) and `/charly-build:build`.

**Build-mode emission is `WriteCandySteps` → `EmitTasks`** in `sdk/deploykit` (`deploykit.Generator`, relocated from `charly/generate.go` in #67, driven by `candy/plugin-build` over the resolved-project envelope + `HostBuild("render-seam")`; the `charly/generate.go` top-level `Generate`/`writeCandySteps` orchestrator is DELETED). `emitTasks` (`charly/tasks.go`) is a thin shim to `deploykit.Generator.EmitTasks` that STAYS for the pod-overlay deploy path (`OCITarget` via `toDeploykit`). The render walks each layer's ops directly to write Containerfile text — NOT the `InstallPlan` IR. Build shares the package-cascade, shell-snippet, and localpkg compiler helpers with the IR (`resolveCascadePackages`, `compileShellSnippetSteps`, `renderLocalPkgImageInstall` — one source of truth, R3), but the overall walk is the direct generator, not a `DeployTarget`. The `InstallPlan` IR + `OCITarget.Emit` is the DEPLOY-mode path: `PodDeployTarget`'s overlay-Containerfile synthesis when `add_candy:` is set, plus the external execution targets. (The local/vm/k8s/android substrates are external out-of-process plugins via `externalDeployTarget`: `deploy:local` (candy/plugin-deploy-local) and `deploy:vm` (candy/plugin-deploy-vm) DO consume the IR — the plugin walks it via `kit.WalkPlans` over the reverse channel, the vm one over the guest `SSHExecutor` so the walk runs inside the guest — while `deploy:k8s` (candy/plugin-kube) does NOT, generating a Kustomize tree host-side.) See `/charly-internals:install-plan` for the IR catalog and `/charly-internals:generate-source` for the Go-level call graph.

**Build-time plugin execution**: `NewGenerator` connects the project's external (out-of-tree) plugin candies (`loadProjectPlugins`) so a `run:` plugin verb — and a plugin builder — is registered + dialable DURING image generation, the SAME loader the deploy/check paths use. A builtin is already registered via `init()` and needs no connect; only an external one is host-built + connected here. `emitTasks` then dispatches a `plugin:` verb step PLACEMENT-AGNOSTICALLY above the registry: a builtin `ProvisionActor` renders an act shell `RUN` in-proc (the zero-JSON fast path), while ANY other resolved provider — an external `grpcProvider`, or a builtin emitting a richer fragment — renders via `emitPluginFragment` → `Invoke(OpEmit)` (in-proc for a builtin, go-plugin gRPC for an external), and the returned `spec.EmitReply.Fragment` is spliced verbatim into the Containerfile (egress-validated with the rest before write). This is operator-authorized build-time execution of host-built plugin code — a project's composed external plugins run as host code during its image builds. Detail → `/charly-internals:plugin` (placement) + `/charly-internals:generate-source`.

**Build-time BUILDER leg (all via `OpResolve`)**: the builder stage emission is `deploykit.Generator.EmitBuilderStages` / `EmitBuilderArtifacts` / `EmitExternalBuilderStages` / `EmitExternalBuilderArtifacts` (relocated from `charly/generate.go` in #67, driven by `candy/plugin-build` over the envelope + `HostBuild("render-seam")`); the builder `OpResolve` resolve helpers (`resolveBuilderStage` / `resolveExternalBuilder` in `charly/generate.go`) STAY, reached via `HostBuild("render-seam")`. These render the four DETECTION-builders' multi-stage (pixi/npm/aur — selected by a candy's `pixi.toml` / `package.json` / `aur:` section; cargo is INLINE) by `Invoke(OpResolve)`ing their plugins — NOT from an in-core `builders.<name>` vocabulary (C10 moved the stage templates into the plugins' `kit.BuilderResolve`). For each detected `(candy, builder)`, `EmitBuilderStages` connects the plugin on-demand (`ensureBuildersConnected`) and calls the shared `resolveBuilderStage` → `prov.Invoke(OpResolve)` with a `spec.BuilderResolveInput` (the host-computed render context — builder ref, stage name, copy src, uid/gid/home, detected manifest/lockfile/build-script, aur packages/options, PRE-RENDERED cache-mount flags) as `op.Params` + a `spec.BuildEnv` as `op.Env`; the returned `spec.BuilderResolveReply.Stage` is written verbatim PRE-main-FROM (cached per `(candy, builder)`), `EmitBuilderArtifacts` writes the cached `CopyArtifacts` + once-per-builder `CopyBinary` POST-main-FROM, and cargo's `InlineFragment` splices in `WriteCandySteps` (deploykit). A candy that instead selects an OUT-OF-TREE builder via its `external_builder: <word>` field gets its multi-stage emitted by `EmitExternalBuilderStages` / `EmitExternalBuilderArtifacts` (run right after their detection counterparts), sharing the SAME `resolveBuilderStage` but sending a MINIMAL input (candy name only): the word resolves through `providerRegistry.ResolveBuilder` to an EXTERNAL `*grpcProvider`, and `resolveExternalBuilder` (the BUILDER-leg analogue of `emitPluginFragment`) requires a non-empty `Stage`. An empty `Stage` (or empty cargo `InlineFragment`), an unresolvable word, or an Invoke error fails LOUDLY (R4) — never a silently-dropped builder stage. Every half is egress-validated with the rest of the Containerfile before write. Detail → `/charly-internals:plugin` (placement) + `/charly-internals:generate-source`.

**Three-phase templates**: the embedded build vocabulary's format (`formats.<fmt>`) and builder (`builders.<name>`) definitions carry a `phases: { prepare, install, cleanup }.{ container, host }` structure. The generator reads `phases.install.container` when set and falls back to the top-level `install_template:` otherwise. The `host:` cell is consumed only when a `SystemPackagesStep` renders on a host venue (`renderHostPackageCommand`) — for the external `local:` AND `vm:` deploys the plugin drives the `SystemPackages` host render via the host's `RunHostStep` channel — never by the generator.

## Quick Reference

| Action | Command | Description |
|---|---|---|
| Generate all | `charly box generate` | Generate Containerfiles for all enabled images |
| With tag | `charly box generate --tag TAG` | Override the image tag |

`charly box generate` takes **no positional image argument** — it always writes the full `.build/` tree for every enabled image in `charly.yml`. To inspect a single image's output, run `charly box generate` (fast — it reuses scratch-stage caches) and then `cat .build/<image>/Containerfile`. Filtering to one image happens implicitly via `charly box build <image>`, which invokes generate internally and then builds only the requested image + its dependencies.

```bash
# Generate all Containerfiles
charly box generate

# Generate with a custom tag
charly box generate --tag v1.2.3

# Inspect generated output
cat .build/fedora/Containerfile
```

## Generated Output

| Path | Description |
|---|---|
| `.build/<image>/Containerfile` | The generated Containerfile — unconditional RUN / COPY / ENV / LABEL directives |
| `.build/<image>/_inline/<layer>/<sha256>` | Inline-content bytes from `write:` tasks (content-addressed, idempotent) |
| `.build/<image>/traefik-routes.yml` | Traefik dynamic config (only for images with `route:` layers) |
| `.build/<image>/<fragment_dir>/*.conf` | Init-system service configs (e.g. `supervisor/`, `systemd/`) |
| `.build/_layers/<name>` | Symlinks to remote layer directories |

All generated files start with `# <path> (generated -- do not edit)`.

## Per-layer emission pipeline

For each layer, `deploykit.Generator.WriteCandySteps` (relocated from `charly/generate.go` in #67) runs this sequence:

```
1. Comment header:    # Layer: <name>
2. ENV from `var:` + ARG TARGETARCH + ENV ARCH=${TARGETARCH} (once per layer)
3. Package install (rpm/deb/pac/aur) — always USER root
4. tasks: iterated in author order:
   a. Resolve ${VAR} in non-verbatim fields
   b. Determine user: (default root)
   c. Emit USER <value> if different from running USER
   d. Dispatch to the verb-specific emitter
   e. Adjacent same-verb same-user tasks coalesce into one directive
      (mkdir, link, setcap) — see /charly-image:layer execution-order section
   f. Parent-dir auto-insertion for copy/write when no earlier mkdir covers
5. Builders (pixi/npm/cargo/aur) — placement is end-of-layer unless an
   explicit `- build: all` task appears in tasks:
6. Reset to USER root (unless last layer and no further root steps follow)
```

### Per-verb emitters (single Go file: `charly/tasks.go`)

| Verb | Emitter | Containerfile output |
|---|---|---|
| `mkdir` | `emitMkdirBatch` | `RUN mkdir -p p1 p2 … [ && chmod <mode> p1 … ]` (one RUN per batch; grouped by mode) |
| `copy` | `emitCopy` | `COPY --from=<layer-stage> --chmod=<mode> [--chown=<uid>:<gid>] <src> <dest>` — **no RUN** |
| `write` | `emitWrite` | `COPY --from=<layer-stage> --chmod=<mode> [--chown=] .build/<image>/_inline/<layer>/<sha256> <dest>` — **no RUN, no shell heredoc** |
| `link` | `emitLinkBatch` | `RUN ln -sf t1 l1 && ln -sf t2 l2 …` (one RUN per batch) |
| `download` | `emitDownload` | `RUN --mount=type=cache,dst=/tmp/downloads bash -c 'export BUILD_ARCH=$(uname -m); curl -fsSL <url> \| <extractor>'` (one RUN per download; `export ...;` termination is required so bash expands `${BUILD_ARCH}` in the URL) |
| `setcap` | `emitSetcapBatch` | `RUN setcap -r … && setcap caps path …` (strip + set chained) |
| `cmd` | `emitCmd` | `RUN --mount=type=bind,from=<layer-stage>,source=/,target=/ctx [--mount=type=cache,…] bash -c $'BUILD_ARCH=$(uname -m)\nset -e\n<command>'` — ANSI-C `$'...'` quoting keeps the multi-line body on one physical line (podman's Dockerfile parser splits at unescaped newlines) |
| `build` | handled inline in `WriteCandySteps` (deploykit) | Existing pixi/npm/cargo/aur multi-stage + inline blocks |
| `plugin` | `ProvisionActor.RenderProvisionScript` (builtin, in-proc) **or** `emitPluginFragment` → `Invoke(OpEmit)` | A builtin act-renderer emits a shell `RUN`; any other resolved provider (external `grpcProvider`, or a fragment-emitting builtin) returns a `spec.EmitReply.Fragment` spliced verbatim. The single seam every Containerfile plugin-step emit flows through; an unresolved verb is a loud error. `plugin: command` is the one exception — its act IS the full `emitCmd` install-task RUN. |

## Cache-mount inheritance

Cache mounts come from the embedded build vocabulary — the `distro:` section (format caches) and `builder:` section (builder caches). `charly tasks.go` picks the right set based on task context:

| Task context | Cache mount(s) |
|---|---|
| `cmd:` as root | Distro format caches (`/var/cache/libdnf5` / `/var/cache/apt` / `/var/cache/pacman/pkg`) + `/ctx` bind mount |
| `cmd:` as non-root | `/tmp/npm-cache` (UID-scoped) + `/ctx` bind mount |
| `download:` | `/tmp/downloads` (shared across layers) |
| Package install | Distro format caches from the embedded `distro:` section |
| pixi builder | `/tmp/pixi-cache` + `/tmp/rattler-cache` (UID-scoped) |
| npm builder | `/tmp/npm-cache` (UID-scoped) |

The `/ctx` bind mount exposes the layer's own directory tree to `cmd:` tasks — so you can still reference `/ctx/<file>` inside an escape-hatch shell block for one-off file access (though `copy:` / `write:` are strongly preferred).

## USER emission

- `user: root` → `USER 0`
- `user: ${USER}` → `USER <numeric UID>` (numeric form avoids an `/etc/passwd` dependency at the switch point)
- `user: <uid>:<gid>` → `USER <uid>:<gid>` (e.g. `1010:1010`)
- `user: <name>` → `USER <name>` (literal; requires user to exist — create via earlier `cmd: useradd` task)

`COPY --chown=` uses numeric `<UID>:<GID>` for `${USER}` (BuildKit-safe), name-pairs for literal users.

## writeBootstrap — adopt vs create

`writeBootstrap` emits the user-creation section of the base-image Containerfile and branches on `ResolvedBox.UserAdopted`:

**Adopt mode** (`UserAdopted = true`) — the base image already ships the declared user; no `useradd` is needed. Emits:

```dockerfile
# User ubuntu (uid=1000) adopted from base image (declared in the embedded charly/charly.yml distro.base_user) — no useradd needed

WORKDIR /home/ubuntu
USER 1000
```

**Create mode** (`UserAdopted = false`) — classic idempotent useradd:

```dockerfile
RUN if ! getent passwd 1000 >/dev/null 2>&1; then \
      (getent group 1000 >/dev/null 2>&1 || groupadd -g 1000 user) && \
      useradd -m -u 1000 -g 1000 -s /bin/bash user; \
    fi

WORKDIR /home/user
USER 1000
```

The pivot is `ResolvedBox.UserAdopted`, set by the `user_policy:` reconciliation in `charly/config.go:ResolveBox`. See `/charly-image:image` "user_policy" for the policy semantics, `/charly-build:build` "base_user:" for the declaration, and `/charly-distros:ubuntu` for the canonical adopt-mode worked example.

Neither branch does destructive metadata mutation (no `usermod -l` rename). Fedora/Arch/Debian always hit the create branch (no `base_user:` declared); Ubuntu under `user_policy: auto` hits the adopt branch.

## Tag-section install emission

Distro-version tag sections like `debian:13:` and `ubuntu:24.04:` are resolved via first-match-wins on the image's `distro:` priority list (e.g. `["ubuntu:24.04", "ubuntu", "debian"]`). Each matched tag section uses the primary format's full install template — so a tag section can carry `repos:`, `keys:`, `options:`, and `package:`, not just packages alone. See `charly/layers.go:TagPkgConfig.Raw` for the map that captures full tag-section YAML, and `/charly-image:layer` for authoring reference.

## ARCH / TARGETARCH emission

Every layer section begins with:

```dockerfile
ARG TARGETARCH
ENV ARCH=${TARGETARCH}
```

`${ARCH}` is then resolvable by BuildKit's ENV substitution in subsequent `COPY` paths, `ENV` values, and inside `RUN` shell. `${BUILD_ARCH}` is uname-style and auto-injected as a shell-local variable at the top of each `cmd:` / `download:` RUN (`BUILD_ARCH=$(uname -m)`), so multi-arch URL templates using either form work without author ceremony.

## Inline-content staging (`write:` verb)

`write: content:` is written to `.build/<image>/_inline/<layer>/<sha256>` at generate time, where `<sha256>` is the SHA-256 of the content. This means:

- **Idempotent:** rewriting the same content is a no-op
- **Content-addressed:** editing the content changes the hash, which changes the COPY source path, which invalidates only that single COPY layer's cache
- **No shell heredoc:** the COPY delivers the bytes directly; no `$`, backticks, or `EOF` markers need escaping

The Containerfile references the file by its relative path: `COPY --from=<layer-stage> --chmod=<mode> .build/<image>/_inline/<layer>/<sha256> <dest>`.

## Behavior

- Generation is idempotent — safe to run repeatedly.
- `.build/` is disposable and gitignored; `charly box generate` will recreate it from scratch.
- Layer dependencies resolve transitively and topologically; circular `require:` is a validation error (surfaced by `/charly-build:validate`).
- Pixi manylinux fix is injected into `pixi.toml` files during the pixi builder stage.
- Multi-stage builds use builder images declared in the embedded `builder:` section (`pixi-builder`, `npm-builder`, `arch-builder` for AUR, etc.).
- Stale `.build/<image>/` directories (from removed or renamed images) are cleaned at the start of each generation.

### LABEL placement (cache efficiency)

All `ai.opencharly.*` LABEL directives are emitted at the **end** of
the final stage, after the last `USER` directive. This means a test or
label edit only re-runs the LABEL steps themselves (metadata-only, ~2
sec) instead of invalidating the buildkit cache for every upstream
RUN/COPY. Particularly important for test authoring: `check:` edits on
a 138-step stack like `immich-ml` cost seconds, not minutes per
iteration. See `/charly-internals:generate-source` "LABEL Placement" for the
rationale and `/charly-check:check` for author-facing workflow implications.

## Bootc-specific generator behaviour

Three emission rules matter specifically for bootc images (those whose `base:` is a bootc container such as `quay.io/fedora/fedora-bootc:43`).

### 1. `initHasFragments` pre-scan gates empty init stages

Each init system defined in the embedded `init:` vocabulary (currently `supervisord` and `systemd`) emits a `FROM scratch AS <stage_name>` scratch stage that layers COPY fragments into, plus an `assembly_template` RUN that bind-mounts from that scratch stage. `sdk/deploykit` (relocated from `charly/generate.go` in #67) pre-scans the layer chain for each init system to check whether any layer contributes fragments (per-entry rendered from the unified `service:` list via `ServiceSchema.ServiceTemplate` / `ServiceSchema.SupportsPackaged`, plus relay configs, plus systemd `.service` files). If none, **both** the scratch stage and the assembly_template RUN are suppressed. Without this, a bootc image with only packaged-unit entries (`use_packaged:`, no rendered body) would emit an empty `FROM scratch AS systemd-services` + a RUN that bind-mounts from it — which fails at build time. The `system_enable_template` and `post_assembly_template` for that init still run — they're independent of the scratch stage.

### 2. `anyRepoHasURL` helper → prepend `dnf5-plugins`

The RPM install_template prepends `dnf install -y dnf5-plugins` whenever any layer `rpm.repos:` entry declares a `url:` (checked via the `anyRepoHasURL` template helper in `charly/format_template.go`). Required because `quay.io/fedora/fedora-bootc:43` strips `dnf5-plugins` (which provides the `config-manager` subcommand) from the default install. Without the prepend, `dnf5 config-manager addrepo --from-repofile=…` — emitted for every URL-based repo — fails with `Unknown argument "config-manager" for command "dnf5"`. `/charly-selkies:ffmpeg` is the canonical URL-repo consumer (adds negativo17's `fedora-multimedia.repo`).

### 3. `export BUILD_ARCH=…;` (not prefix assignment) in `download:` tasks

The `download:` task emits `export BUILD_ARCH=$(uname -m); curl -fsSL "…${BUILD_ARCH}…"` with an explicit semicolon-separator `export`, not the prefix form `BUILD_ARCH=$(uname -m) curl ...`. Bash prefix assignments set the variable in the spawned command's environment **after** the shell has already expanded `${BUILD_ARCH}` in the command's arguments — the expansion sees an unset variable, the URL resolves with an empty arch string, and the download 404s. Source: `charly/tasks.go:envPrefix` with the documenting comment. Layers that use `${BUILD_ARCH}` in a `download:` URL: `/charly-languages:pixi`, `/charly-coder:typst`, `/charly-tools:yay`, `/charly-infrastructure:vectorchord`, `/charly-tools:sherpa-onnx`.

## Project directory override

`charly box generate` resolves `charly.yml` via `os.Getwd()`. Override with `-C <dir>` / `--dir <dir>` / `CHARLY_PROJECT_DIR=<dir>`. See `/charly-image:image` "Project directory resolution".

## Cross-References

### `charly box` family siblings

- `/charly-image:image` -- Family overview + charly.yml composition reference
- `/charly-build:build` -- Building images (calls generate internally)
- `/charly-build:inspect` -- Inspect generated output for a specific image
- `/charly-build:list` -- Enumerate targets before generation
- `/charly-build:merge` -- Post-build layer consolidation
- `/charly-build:new` -- Scaffold a new candy to generate into
- `/charly-build:pull` -- Pull prebuilt images (orthogonal to generate)
- `/charly-build:validate` -- Validation rules for images and layers (including per-verb task rules)

### Related skills

- `/charly-image:layer` — **Canonical task verb catalog, `var:` substitution, YAML anchors, execution order.** Read this first for authoring questions.
- `/charly-check:check` — test-authoring workflow; `check:` blocks are embedded via `writeJSONLabel` and benefit directly from LABELs-at-end cache efficiency.
- `/charly-internals:generate-source` — Deep dive on Containerfile emission internals, `Task` struct, per-verb emitters, `stageInlineContent`, `shellSingleQuote` + `shellAnsiQuote` helpers, LABEL-placement rationale.
- `/charly-internals:go` — Source-code map: `charly/tasks.go` (~430 lines, `emitTasks` shim → deploykit), `sdk/deploykit` (`WriteCandySteps` + `WriteLabels`, relocated in #67), `charly/layers.go` struct definitions.
- `/charly-selkies:ffmpeg` — canonical URL-repo consumer (triggers the `dnf5-plugins` prepend).
