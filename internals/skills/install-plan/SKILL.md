---
name: install-plan
description: |
  The InstallPlan IR — the shared intermediate representation consumed by the DEPLOY
  targets. ALL FIVE deploy substrates (local/vm/pod/k8s/android) are EXTERNAL out-of-process
  deploys via externalDeployTarget over the executor reverse channel. The local AND vm
  substrates DO consume the IR — the plugin walks the InstallPlan over the shared
  out-of-process walk (sdk/kit.WalkPlans), driving the host for host-engine step
  kinds via the RunHostStep reverse-channel RPC; for vm the served executor is the guest
  SSHExecutor, so the SAME walk runs INSIDE the guest. pod's plugin walks NOTHING — pod bakes
  its steps INTO the image, so its substrateLifecycle hook builds the overlay container image
  HOST-SIDE via the retained PodDeployTarget (OCITarget add_candy: synthesis). The
  k8s substrate is EXTERNAL (deploy:k8s, served out-of-process by candy/plugin-kube): it
  does NOT consume the IR — the host preresolver GENERATES a Kustomize tree (the
  GenerateK8sKustomize shim → compiled-in candy/plugin-k8sgen) and the plugin runs `kubectl apply -k`.
  Build-mode Containerfile emission is the SEPARATE writeCandySteps → emitTasks path.
  MUST be invoked before reading or modifying any of:
  charly/install_plan.go, charly/install_build.go, charly/build_target_oci.go,
  charly/deploy_target_pod.go, charly/deploy_target_external.go, charly/vm_lifecycle_preresolve.go,
  charly/substrate_lifecycle_grpc.go, charly/build_overlay.go, charly/k8s_generate.go, charly/k8s_deploy_preresolve.go,
  sdk/spec/deploy_wire.go, or when adding a new step kind / deploy target / reverse-op kind.
---

# InstallPlan IR — shared IR for build + deploy

## Overview

`charly` has several DEPLOY paths that all need to know "what does applying this layer mean?":

1. **Pod deploy** (`pod:` substrate, default) — `charly bundle add <name> <ref>` runs the image via quadlet. Served OUT-OF-PROCESS by `candy/plugin-deploy-pod` (`deploy:pod`), but unlike the others its plugin WALKS NOTHING — pod bakes its steps INTO the image, so its `candy/plugin-deploy-pod` lifecycle (M4) builds the overlay Containerfile (via `OCITarget`/`PodDeployTarget`) HOST-SIDE in `PrepareVenue` and owns the container config/start/remove lifecycle.
2. **Local deploy** (`local:` substrate) — `charly bundle add <name> <ref>` applies the recipe to the destination machine's filesystem (`host: local` → direct shell; `host: <user@machine>` → SSH). Served OUT-OF-PROCESS by `candy/plugin-deploy-local` (`deploy:local`): `externalDeployTarget` hands the plugin this IR, the plugin walks it over the executor reverse channel (`sdk/kit.WalkPlans`), and the host executor is `ShellExecutor` for `host:local`/absent or `SSHExecutor` for `host:<user@machine>` (picked by `rootExecutorForDeployNode`).
3. **VM deploy** (`target: vm`) — `charly bundle add vm:<name> <ref>` applies the recipe inside a running VM over SSH.
4. **Kubernetes deploy** (`target: k8s`) — `charly bundle add <name> --target k8s` emits a Kustomize base/overlays tree.
5. **External out-of-process deploy** — an external deploy-substrate plugin (`externalDeployTarget`) applies on the host venue over the executor reverse channel (`OpExecute`); see "External (out-of-process) deploy target" below.

All these DEPLOY paths are unified behind one IR. A pure compiler (`BuildDeployPlan`) turns `Layer + ResolvedBox + HostContext` into an `InstallPlan`; each deploy path is a `DeployTarget` consuming the plan.

**Boundary-law note.** The `InstallPlan` IR + the deploy wire replies (`VenueDescriptor` / `DeployVenue` / `EmitReply` / `BuilderResolveReply`) ARE the generic **E-envelopes** of the kernel/plugin boundary law (`/charly-internals:plugin` "The kernel/plugin boundary law"): a concrete kind is a PLUGIN that RESOLVES its config into one of these, and the kernel's build/deploy Mechanism consumes the envelope without importing the kind's `spec.<Kind>` type. Adding an IR step kind or a wire field is an ENVELOPE change (kernel); a per-kind `switch` or a `spec.<Kind>` field-read in a consumer is an incomplete seam (a bug to fix), never how a kind reaches the IR.

**Build mode is a SEPARATE path, NOT the IR.** `charly box build` / `charly box generate` emit Containerfiles via the `writeCandySteps` → `emitTasks` generator (per-verb emitters in `charly/tasks.go`), walking each layer's ops directly. It shares the compiler helpers (`resolveCascadePackages`, `compileShellSnippetSteps`, `renderLocalPkgImageInstall` — R3) with the IR, but does NOT walk an `InstallPlan` or use `OCITarget`. `OCITarget` is itself deploy-mode: `PodDeployTarget` constructs it only for `add_candy:` overlay-Containerfile synthesis — invoked HOST-SIDE from `candy/plugin-deploy-pod`'s PrepareVenue (M4) (`BuildDeployPlan` is called only by the deploy command path).

This skill is the single source of truth for the IR shape. Add a new step kind by editing `install_plan.go`, the compiler in `install_build.go`, and each target's `emit*` method — this skill lists every place that needs to stay in sync.

## File layout

| File | Role |
|---|---|
| `charly/install_plan.go` | IR types, enums, `InstallStep` interface, `ReverseOp`, `DeployTarget` interface, `EmitOpts`, `GateEnabled` |
| `charly/install_build.go` | `BuildDeployPlan` pure compiler: `Candy` → `InstallPlan` |
| `charly/build_target_oci.go` | `OCITarget` — emits Containerfile text from the IR; DEPLOY-mode (the `PodDeployTarget` `add_candy:` overlay synthesizer), NOT the `charly box build`/`generate` path. `emitStep` routes the plugin-served build-emit kinds (`pluginEmitStepWords` — the PURE C1.1 kinds + the no-op-emit `reboot` (C1.6) + the HOST-COUPLED `system-packages` (C1.2) + `builder` (C1.3) + `local-pkg-install` (C1.4) + `op` (C1.5)) to the compiled-in `class:step` plugin `candy/plugin-installstep`'s `OpEmit` (via the shared `spliceClassStepEmit`, whose in-proc reverse channel is threaded with the box BUILD-ENGINE context — `stepEmitBuildContext` → `wrapDistroDef(DistroDef)` for SystemPackages + `Generator`/`BuilderConfig`/`Box` for Builder + `ImageBuildDir` for LocalPkgInstall + `ContextRelPrefix` for Op — so a host-coupled step can call back `HostBuild("step-emit", …)`; a no-op-emit word like `apk-install`/`reboot` declares `Emits=false` and `spliceClassStepEmit` skips its `OpEmit` entirely), the ONE remaining in-proc kind (`ExternalPlugin`) to its `StepProvider.EmitOCI`, and an `external:<word>` step to `emitExternalStep` — all splice through the SAME `invokeOpEmitFragment(Opt)` seam (R3) |
| `candy/plugin-installstep` | Compiled-in DUAL-PLACEMENT `class:step` plugin serving the BUILD-context `OpEmit` for the compiler-emitted builtin InstallStep kinds. Two sub-categories: the PURE kinds — `file`/`shell-hook`/`shell-snippet`/`service-packaged`/`service-custom`/`repo-change`/`apk-install` (C1.1) + the no-op-emit `reboot` (C1.6) — whose fragment is pure string formatting from the compiler-produced `spec.InstallStepView` (the SAME view the deploy walk consumes), returned directly from `OpEmit`; and the HOST-COUPLED `system-packages` (C1.2) + `builder` (C1.3) + `local-pkg-install` (C1.4) + `op` (C1.5) kinds, whose `OpEmit` calls back the host `step-emit` host-builder (`Executor.HostBuild`) and echoes the returned fragment, because their render needs the host build engine (`system-packages`: DistroDef format templates; `builder`: the multi-stage `buildStageContext` + `RenderTemplate` engine; `local-pkg-install`: `renderLocalPkgImageInstall` — `buildLocalPkgOnHost` + host-dir staging for a dev bed, the release-download RUN for production; `op`: the RICHEST — `Generator.emitTasks`, the full per-verb render pipeline with COPY staging + op coalescing). `apk-install` and `reboot` declare `Emits=false` (no-op build-emit — an image build installs no apk / reboots nothing). The DEPLOY leg for ALL these kinds is UNCHANGED (`sdk/kit.WalkPlans`; `system-packages` + `builder` + `local-pkg-install` are host-engine via `RunHostStep` → `renderHostPackageCommand` / `runVenueBuilderStep` / `execLocalPkgInstall`; `op` is the act-OpStep `resolveProvisionScript` / `renderOpCommand` path; `reboot` is the host-side guest reboot via `RunHostStep` → `rebootVenueAndWait`) — this plugin serves ONLY `OpEmit`; with C1.6 all 12 compiler-emitted kinds are plugin-served (ExternalPlugin is the 13th, dispatched by its own `class:step` plugin) |
| `charly/deploy_target_pod.go` | `PodDeployTarget` — the RETAINED pod overlay-BUILD engine: synthesizes the overlay Containerfile (via `OCITarget`) when `add_candy:` present, or tags the deploy-name alias when none. Invoked HOST-SIDE by the `overlay` host-builder (`runOverlayBuild`, `build_overlay.go`) that `candy/plugin-deploy-pod`'s PrepareVenue (M4) requests via the F10 `hostBuilders` registry (no longer an inline construction; and no longer an in-proc DeployTarget dispatched by `ResolveTarget`) |
| `charly/build_overlay.go` | `candy/plugin-deploy-pod` — the host-side `pod` venue lifecycle hook (`substrateLifecycle`): `PrepareVenue` REQUESTS the overlay container-image build through the uniform F10 `hostBuilders` registry (the `overlay` builder → `runOverlayBuild`, host-side in-proc via `PodDeployTarget`, the SAME core engine — nothing crosses gRPC; the serializable `spec.OverlayBuildRequest` carries the scalars, the LIVE compiled plans + nested-venue `ParentExec`/`ParentNode` ride the ctx), returns a host-local `ShellExecutor` (the plugin walks nothing); `Start/Stop/Status/Logs/Shell` shell to the CLI; `Rebuild` = `box build`+`check box`+`bundle add`+`stop`+`config`+`start`; `PostTeardown` = `charly remove` + drop overlay images. Served out-of-process by `candy/plugin-deploy-pod` (the FULL wire lifecycle, M4: PrepareVenue via HostBuild("overlay"), Start/Stop/Status/Logs/Shell/Rebuild/PostTeardown via HostBuild("cli"); OpExecute walks nothing) |
| `charly/deploy_chain.go` | `rootExecutorForDeployNode` — picks the root `DeployExecutor` for an external `local:` deploy node (`ShellExecutor` for `host:local`/absent, `SSHExecutor` for `host:<user@machine>`); the `deploy:local` substrate itself is served out-of-process by `candy/plugin-deploy-local`, which walks the plan via `sdk/kit.WalkPlans` |
| `charly/vm_lifecycle_preresolve.go` | the vm `lifecyclePrepareHook` (`vmLifecyclePrepare`: `LoadUnified` → `spec.Vm` + entity + ssh user/port + prior `VmDeployState`, shipped as `spec.LifecyclePrepareInput` — the k8s/android-preresolver-shaped DATA seam) + the vm `lifecyclePostTeardownHook` (the residual ephemeral-lifecycle host cleanup). The vm venue lifecycle ITSELF (boot the domain, build the guest `SSHExecutor`, nested pod-in-guest, teardown, `charly vm` Start/Stop/…/Rebuild) is IMPLEMENTED IN THE PLUGIN `candy/plugin-deploy-vm/lifecycle.go` over `kit` + `HostBuild("cli")` + the served guest executor; the plan WALK likewise runs there via `kit.WalkPlans` over the guest executor (so the same walk runs inside the guest) |
| `charly/deploy_target_external.go` | `externalDeployTarget` — Add/Test/Update/Del for an OUT-OF-PROCESS deploy provider over the executor reverse channel (`OpExecute`); the adapter ALL FIVE external substrates (local/vm/pod/k8s/android) route through; records teardown ops to the ledger keyed on `computeDeployID` |
| `charly/plugin_dispatch_reverse.go` | The F10 reverse legs on `ExecutorService` (host-served on the SAME broker `InvokeWithExecutor` stands up). `InvokeProvider` — PLUGIN↔PLUGIN: the host resolves another provider by (class, word) + Invokes it on the calling plugin's behalf, threading the SAME venue executor into an OUT-OF-PROCESS target via `InvokeWithExecutor` (a fresh nested broker — the generalization of the RunHostStep `ExternalPlugin` arm from OpExecute-only to ANY class/op) or a direct `Invoke` for an in-proc target. `HostBuild` — the calling plugin requests a HOST-side build (the RESOLVE/RENDER engine is in core TODAY — K3 build-engine migration inventory, not permanent core; the box-build podman DRIVE moved into candy/plugin-build in P8b): the host runs the registered `hostBuilder` for `kind` (`registerHostBuilder`/`hostBuilderFor` — TEN registered kinds: `build-resolve` → `hostBuildBuildResolve` (build_resolve_host.go — the box-build loader RESOLVE + Containerfile RENDER seam the candy drive calls) + `merge` → `hostBuildMerge` (build_merge_host.go — the transitional layer-merge seam; deletes when the OCI merge engine externalizes to `verb:oci`), `overlay` → `runOverlayBuild` (build_overlay.go), `step-emit` → `hostBuildStepEmit` (step_emit_hostbuild.go), `plugin-binary` → `buildPluginBinary` (F10), `cli` → `hostBuildCli`, `hostprobe` → `hostBuildHostProbe`, `feature` → `hostBuildFeature`, `settings` → `hostBuildSettings`, `retention` → `hostBuildRetention` (host_build_*.go)). SDK clients: `sdk.Executor.InvokeProvider` / `.HostBuild`. (M13 k8s-gen + M16 egress did NOT use HostBuild — they are compiled-in candies fronted by a host shim, the lighter pattern when the subsystem has no venue-coupled build.) The dispatch + host-build MACHINERY M14/M17 consume; example `candy/plugin-example-dispatch` |
| `charly/substrate_lifecycle_grpc.go` | `grpcSubstrateLifecycle` (F6) — implements the in-core `substrateLifecycle` interface by Invoking an OUT-OF-PROCESS substrate plugin's lifecycle Ops (host→plugin on `Provider.Invoke`: `OpPrepareVenue`/`OpStart`/`OpStop`/`OpStatus`/`OpRebuild`/…). `PrepareVenue`/`TeardownExecutor` re-materialize the plugin's returned `spec.VenueDescriptor` (`{Kind: shell\|ssh, …}`) into a real host-side `ShellExecutor`/`SSHExecutor` — the LIVE executor never crosses the wire; the host rebuilds it and serves THAT over the existing `ExecutorService` to the deploy-walk plugin. Registered (idempotently, never shadowing a compiled-in pod/vm lifecycle) by `registerPluginSubstrateLifecycle` at plugin-load when a `class:deploy` capability declares `lifecycle=true`. The channel M4 reuses to externalize the pod/vm lifecycles. `deploy_preresolve.go` gains the sibling `wireDeployPreresolver` (a `class:deploy` capability with `preresolve=true` → a wire-backed `deployPreresolver` Invoking `OpPreresolve`, generalizing the in-core k8s/android preresolvers). Both registries are now `sync.RWMutex`-guarded for the plugin-load mutation. Example: `candy/plugin-example-lifecycle` (out-of-process-only) |
| `charly/plugin_step_external.go` | `externalPluginStepProvider` — the `StepProvider` for `StepKindExternalPlugin` (a plugin-verb `run:` step — authored as `<word>: <input>` sugar, desugared to the internal `plugin`/`plugin_input` op — served by an OUT-OF-PROCESS plugin): `EmitOCI`→`Invoke(OpEmit)` is the only in-proc Emit (the image-build / pod-overlay Containerfile fragment). At DEPLOY time the step is executed via the `executeExternalPluginStep` seam — `Invoke(OpExecute)` WITH the host's executor over the reverse channel, recording the reply's dynamic `ReverseOp`s to the `CandyRecord`; the external local/vm deploy walks reach it as a host-engine step over `RunHostStep`. The `executorInvoker` capability is the discriminator |
| `charly/step_emit_hostbuild.go` | F-STEP-EMIT: the generic `step-emit` HostBuild builder for a HOST-COUPLED step's build-context fragment — `registerHostBuilder("step-emit", hostBuildStepEmit)` dispatches by step WORD to the `stepEmitters` per-word registry (`registerStepEmitter`), returning a `spec.EmitReply`. The BUILD-context sibling of the `overlay`/`build-resolve` host-builders. C1.2 registered the FIRST emitter — `system-packages` (`stepEmitSystemPackages`: reconstructs the step from the view, resolves the FormatDef via the box `DistroCfg`.`FindFormat`, renders the `phase.install.container` template); C1.3 registered the SECOND — `builder` (`stepEmitBuilder`: reconstructs the `*BuilderStep`, computes the render context via `Generator.buildStageContext`, then renders the multi-stage / inline fragment via `kit.BuilderResolve` for the externalized builders (pixi/npm/aur/cargo, C10) — a custom builder via `RenderTemplate` on its vocabulary `stage_template`/`install_template` — reading the threaded `Generator`/`BuilderConfig`/`Box` off the `buildEngineContext`); C1.4 registered the THIRD — `local-pkg-install` (`stepEmitLocalPkgInstall`: reconstructs the `*LocalPkgInstallStep`, calls the SAME `renderLocalPkgImageInstall` the image build uses — dev switch off `Generator.DevLocalPkg`, `boxName` off `Box.Name`, `imageDir` off the threaded `ImageBuildDir`); C1.5 registered the FOURTH and RICHEST — `op` (`stepEmitOp`: reconstructs the `*OpStep`, resolves the candy via `Generator.candyByName`, and drives the SAME `Generator.emitTasks` the box build uses — COPY staging, inline-content staging, mkdir/link/setcap coalescing, the act-verb `case "plugin"` seam — reading the threaded `Generator`/`Box`/`ImageBuildDir`/`ContextRelPrefix`). A PURE step never reaches it (its OpEmit returns the fragment directly) |
| `sdk/spec/deploy_wire.go` | The deploy IR wire types shared with the plugin SDK: `Scope`, `ReverseOp` (+ `ReverseOpPluginScript`), `InstallPlanView`, `DeployVenue`, `DeployReply`, plus the build-time `BuildEnv` / `EmitReply` (verb/step `OpEmit`) / `StepEmitRequest` (F-STEP-EMIT: the `HostBuild("step-emit", …)` envelope for a host-coupled external step — `{Word,Payload,Distros}`) / `BuilderResolveReply` (builder `OpResolve`: `{Stage, CopyArtifacts}`) / `BuildRequest` + `BuildReply` (the BUILD-ENGINE DISPATCH envelope for the `build:box` / `build:generate` plugin's `OpBuild` HostBuild call — `charly box build`/`generate`; see `/charly-internals:plugin`) / `OverlayBuildRequest` + `OverlayBuildReply` (the pod-overlay dispatch envelope for the F10 `overlay` host-builder — `candy/plugin-deploy-pod`'s PrepareVenue (M4); scalars only, the live plans + venue ride the ctx) |
| `charly/plugin_prescan.go` | The byte-gated, additive parse pre-scan that recognizes an EXTERNAL deploy SUBSTRATE word at config-parse time, before the provider connects |
| `charly/k8s_generate.go` | `GenerateK8sKustomize` — now a thin in-core SHIM (M13): lifts the 3 caps scalars + `spec.Deploy`/`spec.K8s` into `spec.K8sGenInput`, Invokes the compiled-in `candy/plugin-k8sgen` (`verb:k8sgen`/`OpEmit`) for the manifest docs, validates each HOST-SIDE via the M16 egress shim, writes the `base/`+`overlays/` tree. Called by the k8s deploy preresolver + `from-box --target k8s` (unchanged signature), NOT a `DeployTarget`. The generator itself lives in `candy/plugin-k8sgen/k8sgen.go` |
| `charly/k8s_deploy_preresolve.go` | the HOST-side `deploy:k8s` preresolver (F1) — resolves the image Capabilities + the kind:k8s cluster template, runs `GenerateK8sKustomize`, and ships the overlay path in `DeployVenue.Substrate` (`spec.K8sDeployVenue`) for the out-of-process candy/plugin-kube `deploy:k8s` provider |
| `sdk/kit/deploy_executor*.go` | `DeployExecutor` interface + `ShellExecutor` + `SSHExecutor` — shell + file-copy abstraction (the core `SSHExecutor.WaitFor*` are thin delegates to `sdk/kit`'s `WaitForSSH` / `WaitForCloudInit` / `WaitForPackageLock`). The external `vm` deploy's `OpPrepareVenue` builds the guest `SSHExecutor` the reverse channel serves; a `local: {host: user@machine}` remote also uses `SSHExecutor` |
| `charly/install_plan_test.go` | IR unit tests (scope/venue/gate/reverse derivations) |
| `charly/install_build_test.go` | Compiler integration tests (ripgrep, dev-tools, pixi layer) |

## Core types

### `InstallPlan`

```go
type InstallPlan struct {
    DeployID       string       // per-deploy hash of image + add_layers
    Image          string
    Version        string       // layer/image CalVer
    Distro         string       // "fedora:43"
    Layer          string       // set for per-layer plans; "" for merged whole-image plans
    Steps          []InstallStep
    CandiesIncluded []string     // ordered topo-sorted layer names (for merged plans)
    AddCandies      []string     // refs added via charly.yml add_candy: (for provenance)
    BuilderImage   string       // selected builder for VenueContainerBuilder steps
    Meta           map[string]string
}
```

One plan per layer when the compiler runs on a single `Candy`. For whole-image deploys, `MergePlan(plans, image, addCandies)` merges per-layer plans while preserving layer boundaries for refcount bookkeeping. `DeployID` is a deterministic 16-hex-char sha256 prefix over `(image, layer_order, add_layers)` — same inputs → same ID, so re-deploys are stable.

### `InstallStep` interface

```go
type InstallStep interface {
    Kind() StepKind
    Scope() Scope
    Venue() Venue
    RequiresGate() Gate
    Reverse() []ReverseOp
}
```

All thirteen builtin concrete step kinds (plus the open `external:<word>` family — F3's `externalStep`) implement this interface. `Reverse()` is called at install time (not teardown) so the ledger records the exact reversal ops tied to the specific artifacts created. (`ExternalPluginStep` is the exception that proves the rule: its `Reverse()` is static-nil — its reversal ops are DYNAMIC, recorded from the plugin's `OpExecute` reply at emit time, not from the step itself.)

### Enums

**`Scope`** — where the effect lands:
- `ScopeSystem` — `/etc`, `/usr`, `/var`; requires sudo on host; `USER root` in Containerfile.
- `ScopeUser` — `$HOME/.pixi`, `$HOME/.cargo`, `$HOME/.local`, user-scope systemd units.
- `ScopeUserProfile` — shell init surface (`~/.bashrc` / `~/.zshenv` / fish conf.d + `~/.config/opencharly/env.d/`).

**`Venue`** — where commands physically execute:
- `VenueHostNative` — host shell (plain or sudo-wrapped) or a plain `RUN` in Containerfile.
- `VenueContainerBuilder` — inside a builder container: `FROM <builder> AS stage` in Containerfile; `podman run <builder>` on host target.
- `VenueSkip` — recorded with reason but not executed (container-runtime-only fields on host target; `aur:` on non-Arch hosts).

**`Phase`** — three-phase template execution:
- `PhasePrepare` — repo config, key import, copr enable.
- `PhaseInstall` — the actual package-manager or builder invocation.
- `PhaseCleanup` — teardown (copr disable, cache wipe).

Each `SystemPackagesStep` carries one phase; `--allow-repo-changes` gating is a simple lookup on `step.Phase == PhasePrepare`.

**`Gate`** — opt-in flag name:
- `GateNone` (default, always enabled)
- `GateAllowRepoChanges`
- `GateAllowRootTasks`
- `GateWithServices`

Gates apply only to the host target. `EmitOpts.AssumeYes` enables all three. See `GateEnabled(gate, opts)` in `install_plan.go`.

**`StepKind`** — discriminator for concrete types:
- The CLOSED builtin set: `SystemPackages`, `Builder`, `Op`, `File`, `ServicePackaged`, `ServiceCustom`, `ShellHook`, `ShellSnippet`, `RepoChange`, `ApkInstall`, `LocalPkgInstall`, `Reboot`, `ExternalPlugin`.
- The OPEN external family (F3): `external:<word>` — a PLUGIN-contributed step kind served by a `class:step` provider. Not a fixed enum entry; carried OPAQUELY (see `externalStep` in the table below).

The Go-internal builtin vocabulary is the `allStepKinds` slice in `provider_step.go` (all thirteen kinds — each round-trips through `stepToView`/`stepFromView`, the deploy view). `checkStepProviderBijection` asserts every kind is SERVED, split by how: a kind in `pluginEmitStepWords` (the plugin-served build-emit kinds — the PURE `File`/`ShellHook`/`ShellSnippet`/`ServicePackaged`/`ServiceCustom`/`RepoChange`/`ApkInstall` (C1.1) + the no-op-emit `Reboot` (C1.6, `Emits=false`) + the HOST-COUPLED `SystemPackages` (C1.2) + `Builder` (C1.3) + `LocalPkgInstall` (C1.4) + `Op` (C1.5) — 12 kinds) resolves to a compiled-in `class:step` plugin declaring a `StepContract` (`candy/plugin-installstep`, NO in-proc `StepProvider`); the ONE remaining kind (`ExternalPlugin`) resolves to its in-proc `StepProvider` (its `EmitOCI`). Add an in-proc kind → add it to `allStepKinds` + a dedicated `StepProvider`; externalize a kind's build-emit → move it to `pluginEmitStepWords` + the plugin. An `external:<word>` kind is NOT in `allStepKinds` and registers no per-word `StepProvider` — it is recognized by the `external:` prefix (`isExternalStepKind`) and dispatched by the OPEN DEFAULT ARM in `kit.WalkPlans` + `RunHostStep`, so the closed bijection deliberately never sees it.

The IR carries no image-fetch step kind. Deploys (any target) emit
zero image-pull / image-build steps; test-bed image preflight is a
separate, check-time concern handled by `charly/check_image_preflight.go`
(CLAUDE.md "Deploy fetches NOTHING speculative").

## The step kinds (thirteen builtin + the open `external:<word>` family)

| Kind | What it carries | Venue default | Scope derivation |
|---|---|---|---|
| `SystemPackagesStep` | Format (rpm/deb/pac), Phase, Packages, Repos, Options, Copr, Modules, Exclude, Keys, CacheMounts | HostNative | Always system |
| `BuilderStep` | Builder (pixi/npm/cargo/aur), BuilderImage, CandyDir, Phase, Artifacts, RawStageContext | ContainerBuilder | aur→system, others→user |
| `OpStep` | Op (raw), CandyName, CandyDir, CtxPath, ResolvedUser | HostNative | From ResolvedUser (root or 0 → system; else user) |
| `FileStep` | Source, Dest, Mode, Owner, CandyName | HostNative | `pathIsSystemScoped(Dest)` |
| `ServicePackagedStep` | Unit, TargetScope, Enable, OverridesText, OverridesPath, CandyName, PriorEnabled | HostNative | TargetScope field |
| `ServiceCustomStep` | Name, UnitText, UnitPath, TargetScope, Enable, CandyName | HostNative | TargetScope field |
| `ShellHookStep` | CandyName, EnvVars, PathAdd, EnvFile | HostNative | Always user-profile |
| `ShellSnippetStep` | CandyName, Origin, Shell (bash/zsh/fish/sh), Snippet, PathAppend, Destination, Marker, UseDropin, Priority | HostNative | `pathIsSystemScoped(Destination)` (system for container drop-ins, user-profile for ~/.bashrc etc.) |
| `RepoChangeStep` | Format, File, Content, Checksum, CandyName | HostNative | Always system |
| `ApkInstallStep` | Packages (apk specs), CandyName, CandyDir | HostNative | Always system. Only `target: android` executes it; every other target records a skip. |
| `LocalPkgInstallStep` | PkgbuildRef, CandyName, CandyDir, ProjectDir, Format, LocalPkg (`*LocalPkgDef`) | HostNative | Always system. Compiled from a layer's per-format `localpkg:` map (the `charly` layer's `{pac: pkg/arch, rpm: pkg/fedora, deb: pkg/debian}`) at "step 2.5" (before tasks); `compileLocalPkgStep` resolves the target distro's format FIRST (`DistroDef.LocalPkgFormat`), then the layer's source for that format, so `Format` + `LocalPkg` come from the `format.<fmt>.local_pkg:` block in the embedded `charly/charly.yml` — EVERY command rendered from config, no hardcoded build/install/glob literals. On a localpkg-capable deploy target (`target: local` / `target: vm`) the HOST builds the format's source via `LocalPkg.BuildTemplate` (pac → `makepkg`; rpm/deb → a distro-matched podman container) into `LocalPkg.PkgGlob` artifacts, then installs them onto the target via `LocalPkg.InstallTemplate` — the format's AUTO-RESOLVING local-file install (`pacman -U` / `dnf install` / `apt-get install`), which pulls the package's repo deps automatically. There is NO dependency-closure builder (the aur-LAYER deploy path still reuses the shared `buildDepPkgsOnHost`/`transferAndInstallPkgs` leg, R3). `LocalPkg.Probe` gates the install leg; `LocalPkg.SourceSentinel` (`PKGBUILD`/`*.spec`/`debian/control`) marks the source dir. `resolveLocalPkgDir` walks up from `ProjectDir`, so a consumer nested under `box/<distro>` finds the superproject `pkg/<fmt>`. At IMAGE build the install is **mode-switched by box type** (unified in `renderLocalPkgImageInstall`, shared by `generate.go writeCandySteps` (the `charly box build`/`generate` image build) + the host `step-emit` seam `stepEmitLocalPkgInstall` (the pod-overlay build-emit, routed through `candy/plugin-installstep`'s `step:local-pkg-install` `OpEmit` since C1.4) — R3): a PRODUCTION box DOWNLOADS the published release (`LocalPkg.DownloadTemplate`), while a DISPOSABLE check bed BUILDS the package from LOCAL in-development source and COPYs it in — see "Check-vs-production charly toolchain" below. Skipped only on a distro with no localpkg-capable format (the layer's task fallback). Machinery: `charly/localpkg.go`; config: the embedded `charly/charly.yml` `format.<fmt>.local_pkg:` block. |
| `RebootStep` | CandyName | HostNative | Always system; `Reverse()` empty. Emitted last when a layer sets `reboot: true`. Its BUILD-emit is a plugin-served no-op (`pluginEmitStepWords[Reboot]="reboot"` → `candy/plugin-installstep`, `Emits=false` — an image build reboots nothing, C1.6; NO in-proc `StepProvider`, mirroring `ApkInstall`). Its DEPLOY leg is unchanged: only the external `vm` deploy reboots — its `candy/plugin-deploy-vm` walk drives the step host-side over `RunHostStep` → `rebootVenueAndWait`, where the host reboots the guest + waits for the deterministic boot_id change (a rebootable venue). OCI/pod/k8s skip; the external `local:` deploy skips + warns (never reboots the operator host). |
| `ExternalPluginStep` | Op (the desugared plugin-verb op — verb word + internal `plugin_input` + `RunAs`), CandyName, ResolvedUser, Distros | HostNative | From ResolvedUser (`opStepScope`: root/empty → system; else user). `Reverse()` static-nil — teardown ops are recorded DYNAMICALLY from the plugin's `OpExecute` reply. A plugin-verb `run:` step (authored `<word>: <input>`) whose verb is served by an EXTERNAL (out-of-process) `class:verb` plugin — see "ExternalPluginStep notes" below. |
| `externalStep` (F3, kind `external:<word>`) | Word, ScopeV/VenueV/GateV (plugin-DECLARED), Payload (opaque `json.RawMessage`), CandyName, reverseOps (dynamic) | DECLARED (StepContract.venue) | DECLARED (StepContract.scope) — advisory, since the plugin self-execs `RunSystem`/`RunUser`. A PLUGIN-CONTRIBUTED step kind: a plugin-word `run:` step (authored `<word>: <input>`) whose word is a `class:step` provider declaring a `StepContract`. `compileActOp` lowers it (resolve(ClassStep) + the carrier's contract → `externalStep` with the opaque desugared `plugin_input` as Payload) — **only when the word is NOT a verb (verb-first precedence)**: a plugin-word step whose word resolves as a `class:verb` is a verb act (falls through to `OpStep`), so a `class:step` word COLLIDING with a verb word (`file` = `verb:file` act + `step:file` build-emit, C1.1) resolves as the VERB, never a spurious `external:file`; `stepToView`/`stepFromView` round-trip it with the Scope/Venue/Gate AUTHORITATIVE (not recomputed); the host's OPEN DEFAULT ARM in `kit.WalkPlans` + `RunHostStep` dispatches it via `executeExternalStep` → `Invoke(OpExecute)` over the SAME reverse channel `ExternalPluginStep` uses (R3, `invokeStepExecute`). `Reverse()` returns the dynamic ops recorded from the reply. THE carrier M2 reuses to externalize the builtin step kinds. The `StepContract` declaration rides `ProvidedCapability.step_contract` over Describe (`sdk/proto`); example: `candy/plugin-example-stepkind`. **BUILD leg (F-STEP-EMIT):** `StepContract.Emits` (proto `step_contract.emits`) declares the step produces a build-context Containerfile FRAGMENT; the pod-overlay `OCITarget.emitStep` OPEN external-step arm (`emitExternalStep`, `build_target_oci.go`) resolves the `class:step` provider by the trimmed word, and for `Emits=true` Invokes `OpEmit` (via the SHARED `invokeOpEmitFragment` seam — R3, the SAME path `emitPluginFragment` takes) and splices the fragment; `Emits=false` → skip (a deploy-only external step, like apk on an image build). A HOST-COUPLED step (fragment needs the host build engine) has its OpEmit call back `HostBuild("step-emit", spec.StepEmitRequest{Word,Payload,Distros})` → the `stepEmitters` per-word registry (`registerStepEmitter`, `step_emit_hostbuild.go`) — the BUILD-context sibling of the `overlay`/`image` host-builders (C1.2 registered `system-packages` there; the compiler-emitted `SystemPackagesStep` uses this path via `pluginEmitStepWords`, not the `external:<word>` arm). |

**Build-emit externalization (C1.1) — the seven PURE kinds.** `FileStep`, `ShellHookStep`,
`ShellSnippetStep`, `ServicePackagedStep`, `ServiceCustomStep`, `RepoChangeStep`, and
`ApkInstallStep` keep their typed structs + `Scope()`/`Venue()`/`Reverse()` methods (they still
compile from candy fields and project to the deploy view), but their pod-overlay BUILD-emit no
longer lives in an `OCITarget.emit*` method — it moved to the compiled-in `class:step` plugin
`candy/plugin-installstep`. `OCITarget.emitStep` maps each kind to the plugin word via
`pluginEmitStepWords`, serializes the step VIEW (`stepToView`) as the `OpEmit` payload, and splices
the plugin's fragment. The plugin decodes `spec.InstallStepView` and renders the SAME string the
former `emitFile`/`emitShellHook`/… produced (pure formatting — no host build engine). Their DEPLOY
leg is UNCHANGED (`kit.WalkPlans` `walkFile`/`walkShellHook`/… render from the same view). This is
build-emit-only externalization: full externalization (compiler → `externalStep`, deploy via
`OpExecute`) is the later M2 carrier above.

**Build-emit externalization (C1.2/C1.3/C1.4/C1.5) — the HOST-COUPLED `SystemPackagesStep` + `BuilderStep` + `LocalPkgInstallStep` + `OpStep`.** The
same build-emit-only pattern extends to the HOST-COUPLED kinds: each keeps its typed struct + methods +
native compile (`compileSystemPackageSteps` / `compileBuilderSteps` / `compileLocalPkgStep` / `compileActOp` for Op) and its UNCHANGED deploy leg
(host-engine via `RunHostStep` → `renderHostPackageCommand` for SystemPackages, → `runVenueBuilderStep`
for Builder, → `execLocalPkgInstall` for LocalPkgInstall; the act-OpStep `resolveProvisionScript` / `renderOpCommand` path for Op), but its pod-overlay BUILD-emit moved off `OCITarget` into `candy/plugin-installstep`
(`pluginEmitStepWords[SystemPackages] = "system-packages"`, `pluginEmitStepWords[Builder] = "builder"`, `pluginEmitStepWords[LocalPkgInstall] = "local-pkg-install"`, `pluginEmitStepWords[Op] = "op"`).
UNLIKE the seven PURE kinds, their render needs the host build ENGINE — SystemPackages the `DistroDef`
format templates + `RenderTemplate` (C1.2); Builder the multi-stage `Generator.buildStageContext` +
`RenderTemplate` engine + the `BuilderConfig` registry + the box `ResolvedBox` (C1.3); LocalPkgInstall the
host localpkg build engine `renderLocalPkgImageInstall` (→ `buildLocalPkgOnHost` + host-dir staging for a dev
bed, the release-download RUN for production) reading `Generator.DevLocalPkg` + `Box.Name` + `ImageBuildDir`
(C1.4); Op the RICHEST — `Generator.emitTasks`, the full per-verb render pipeline (COPY from the layer scratch
stage, content-addressed inline-content staging, mkdir/link/setcap coalescing, the act-verb `case "plugin"`
seam) reading the scanned `Generator.candyByName` + the box `ResolvedBox` + `ImageBuildDir` + `ContextRelPrefix`
(C1.5) — which cannot cross the process boundary, so the plugin's `OpEmit` calls back the host `step-emit` host-builder
(`Executor.HostBuild`) and echoes the returned `EmitReply`. The in-core renders
(`stepEmitSystemPackages` / `stepEmitBuilder` / `stepEmitLocalPkgInstall` / `stepEmitOp`, `step_emit_hostbuild.go`) reconstruct the step from the
view and reuse the SAME resolvers/pipeline the former in-proc `OCITarget` build-emit used (byte-equivalent):
SystemPackages via `DistroCfg.FindFormat` → `phase.install.container`; Builder via `buildStageContext` →
`kit.BuilderResolve` (C10 — the SAME render the box-build path + the plugin's OpResolve use for the
externalized pixi/npm/aur multi-stage + cargo inline; a custom builder still via its vocabulary
`stage_template`/`install_template`); LocalPkgInstall via the SAME
`renderLocalPkgImageInstall` `generate.go writeCandySteps` calls for the image build; Op via the SAME
`Generator.emitTasks` `writeCandySteps` calls for the box build. The Builder engine (`Generator` /
`BuilderConfig` / `Box`) + the LocalPkgInstall `ImageBuildDir` + the Op `ContextRelPrefix` are threaded onto the reverse channel via the `buildEngineContext` fields
`OCITarget.stepEmitBuildContext` populates.

**Build-emit externalization (C1.6) — the no-op-emit `RebootStep` — COMPLETES the 13-step set.** `RebootStep`
keeps its typed struct + `Scope()`/`Venue()`/`Reverse()` (empty) methods and its UNCHANGED deploy leg (the
host-side guest reboot over `RunHostStep` → `rebootVenueAndWait`, gated on the rebootable-VM-venue flag), but
its pod-overlay BUILD-emit moves off the last in-proc `rebootStepProvider.EmitOCI` (deleted) into
`candy/plugin-installstep` (`pluginEmitStepWords[Reboot] = "reboot"`). UNLIKE the HOST-COUPLED kinds it needs
NO host build engine and NO `stepEmitter`: a reboot has no meaning in an image build, so it is a NO-OP-emit
kind exactly like `ApkInstall` (C1.1) — it declares `Emits=false`, and `spliceClassStepEmit` skips its
`OpEmit` entirely (the plugin's `renderFragment` returns an empty fragment as a belt-and-suspenders
fallback). With C1.6 landed, the LAST host-coupled step kind's build-emit is externalized: EVERY builtin
InstallStep kind is now plugin-served — the 12 compiler-emitted kinds via `candy/plugin-installstep`, and
`ExternalPlugin` (the 13th) via its own per-verb `class:step` plugin dispatch — leaving `ExternalPlugin` the
ONLY kind with an in-proc `StepProvider.EmitOCI`.

**`compileActOp` non-regression (the C1.1 verb-first fix).** C1.5 moves ONLY the `OpStep` BUILD-emit; `compileActOp`
(`install_build.go`) is UNCHANGED. A plugin-verb `run:` step (authored `<word>: <input>`) still lowers to a native
`OpStep` (verb-first precedence: an in-proc `ProvisionActor` / `command` verb wins over a colliding `step:` word —
the reason a `file:` step is the file VERB act, never an `external:file` step), and its DEPLOY leg still renders via
`resolveProvisionScript` / `renderOpCommand`. `op` joins the compiler-emitted step-word set (never authorable —
no `op:` verb sugar exists), so it cannot
regress the verb-first path (`TestCompileActOp_VerbWordWinsOverCollidingStepWord`).

### Check-vs-production charly toolchain (the `--dev-local-pkg` distinction)

A `localpkg:` candy (the `charly` toolchain) installs the charly binary as a
proper OS package on every distro image. The BINARY SOURCE depends on the box
type — a hard, GENERIC distinction, NEVER mixed, decided in ONE place
(`renderLocalPkgImageInstall`, `charly/localpkg.go`):

| Box type | charly binary source | How |
|---|---|---|
| **Disposable check box** (a `disposable: true` deploy) | latest **in-development** | the check-bed runner ALWAYS passes `charly box build --dev-local-pkg`, so the localpkg is BUILT from local source (`pkg/<fmt>` + `charly/`, via `buildLocalPkgOnHost`) and COPY'd into the image — a bed tests the charly code under development |
| **Production box** (any normal `charly box build`) | latest **published** | the default: the localpkg DOWNLOADS the published release (`releases/latest/download/opencharly-<arch>.<fmt>`) |

Both install via the SAME dep-resolving `InstallTemplate` (`pacman -U` / `dnf
install` / `apt-get install`) — only the package SOURCE differs, so the toolchain
is OS-tracked either way. The switch flows through `Generator.DevLocalPkg` ←
`BuildCmd.DevLocalPkg` (`--dev-local-pkg`); the check-bed runner sets it for EVERY
bed image build (`candy/plugin-check/bed_run.go`, driving `charly box build` over
the `HostBuild("cli")` seam), a production build never does. Generic
across all kinds + all localpkg candies. A dev build that cannot locate its local
source **HARD-ERRORS** — it NEVER silently falls back to the release (R4), so a
bed can never accidentally test a stale published binary. Net: a disposable check
bed always exercises the in-development charly; a real box ships the released one.

**`ShellSnippetStep` notes:**
- Compiled by `compileShellSnippetSteps` in `install_build.go` — applies the per-shell-wins-over-generic selection rule from `layer.Shell()`.
- OCITarget emits a `RUN mkdir -p ... && cat > <dest> <<EOF` heredoc with a sha256-derived end-marker (anti-collision).
- The external `local:` (`candy/plugin-deploy-local`) and `vm:` (`candy/plugin-deploy-vm`) deploy walks — the SAME `kit.WalkPlans`, the vm one over the guest `SSHExecutor` — probe `command -v <shell>` once at the top of the walk; absent shells become VenueSkip-style no-ops with a logged reason. UseDropin=true → whole-file write; UseDropin=false → the kit walk's managed-block splice (`sdk/kit/profile.go`) against the existing rc file with a per-layer marker.
- Reverse: `ReverseOpRmFileSystem` / `ReverseOpRmFileUser` for drop-ins; `ReverseOpRemoveManaged` (with `Extra["marker"]=CandyName`) for managed-block append.
- Round-trip: `LabelShell` (`ai.opencharly.shell`) carries the merged set; `CollectShell` builds it at `charly box build` time, `ExtractMetadata` parses it at deploy time, `MergeDeployShell` overlays charly.yml entries by id.

**`ExternalPluginStep` notes** (`charly/plugin_step_external.go`, `externalPluginStepProvider`):

- **What it is.** The install-timeline IR node for a plugin-verb `run:` step (authored `<word>: <input>`) whose verb is served by an EXTERNAL (out-of-process) plugin — a `grpcProvider`, not a built-in `TypedStepProvider` (package/service) nor a `ProvisionActor` (the state-provision shell verbs) nor the `command` install verb. It is operator-authorized build/deploy-time plugin execution: the candy author opted in by composing the verb-step.
- **Routing (`compileActOp`, `install_build.go`).** A `plugin:` verb resolves through `providerRegistry.ResolveVerb`; if its provider is NOT a `TypedStepProvider` but DOES satisfy `executorInvoker` (an `InvokeWithExecutor` method, implemented SOLELY by the out-of-process `grpcProvider`), it routes to `ExternalPluginStep`. Every builtin `ProvisionActor` verb and `command` fall through to the generic `OpStep` path, unchanged. The `executorInvoker` capability is the precise discriminator — it mirrors the build-context `BuildEmitter` marker (`provider_verb.go`), placement-agnostic above the registry.
- **EmitOCI — the BUILD venue** (image build / pod-overlay Containerfile): `Invoke(OpEmit)` via the SHARED `emitPluginFragment` seam (R3 — the SAME path `tasks.go`'s `emitTasks` `case "plugin"` takes for an external verb), splicing the plugin's Containerfile FRAGMENT verbatim. It cannot deploy-execute at build (no live venue); a deploy-only plugin (empty `OpEmit` fragment) fails loudly at `emitPluginFragment`'s empty-fragment guard, never bakes nothing silently.
- **The DEPLOY venue — `executeExternalPluginStep`** (the install runs ON the target, not into an image): there is NO `EmitLocal`/`EmitVM` on `StepProvider` (only `EmitOCI` remains — both deploy venues externalized with `target:local`/`target:vm`). When the external `local:`/`vm:` deploy walk reaches an `ExternalPluginStep` (a host-engine step), the host drives it over `RunHostStep` → `executeExternalPluginStep`: `Invoke(OpExecute)` WITH the live `DeployExecutor` on the go-plugin broker (the E3b reverse channel), so the plugin runs its deploy-context effect (RunSystem/RunUser) on the real venue it cannot hold across the process boundary, and RETURNS its teardown `ReverseOp`s. The host appends `reply.ReverseOps` to the `CandyRecord` in the HOST-side ledger (keyed by `computeDeployID`, like every external deploy — for a vm deploy too, NOT a guest-side ledger) — record-and-replay: only recorded ops are reversed at `charly bundle del`, reusing the SAME `spec.DeployReply` / `ReverseOp` wire as the external deploy TARGET (`deploy_target_external.go`, R3). `plugin_input` rides `op.Params` UNWRAPPED; a `spec.DeployVenue` rides `op.Env`. A `DryRun` short-circuits BEFORE the wire call (Invoke IS the apply).
- **`OpExecute` is the deploy-context counterpart of `OpEmit` (build).** Same verb-step, two legs: bake a Containerfile fragment at build (`OpEmit`), or execute the effect on a live `local:`/`vm:` target at deploy (`OpExecute`) — picked by venue, placement-agnostic.
- **Self-registers** via `registerDedicatedBuiltin(externalPluginStepProvider{})`, like every other dedicated step provider; the `StepProvider` it implements lives in `provider_step.go`.

Each step's `Reverse()` emits typed `ReverseOp` values. Adding a step kind means: (a) define the struct in `install_plan.go`, (b) decide its Scope/Venue/Gate/Reverse, (c) wire its BUILD-emit through a `class:step` plugin `OpEmit` referenced from `pluginEmitStepWords` (`candy/plugin-installstep`) — a PURE kind renders the fragment directly from the step VIEW (the C1.1 pattern; a no-op-emit kind like `ApkInstall`/`Reboot` declares `Emits=false` and renders an empty fragment, so `spliceClassStepEmit` skips its `OpEmit`), a HOST-COUPLED kind (whose render needs the host build engine) instead calls back `HostBuild("step-emit", …)` and registers an in-core `stepEmitter` via `registerStepEmitter` (the C1.2/C1.3/C1.4/C1.5 pattern, `stepEmitSystemPackages` / `stepEmitBuilder` / `stepEmitLocalPkgInstall` / `stepEmitOp`; thread whatever engine it needs onto `buildEngineContext` via `stepEmitBuildContext`); a still-in-proc kind keeps an in-proc `StepProvider.EmitOCI` (only `ExternalPlugin` remains such after C1.6) — plus its DEPLOY leg in the shared `sdk/kit.WalkPlans` (and `RunHostStep` if it is a host-engine kind), (d) ensure the compiler in `install_build.go` emits it.

## The compiler — `BuildDeployPlan`

```go
func BuildDeployPlan(layer *Candy, img *ResolvedBox, hostCtx HostContext) (*InstallPlan, error)
```

Pure — no I/O, no side effects. Given the same inputs, produces the same plan. Called ONLY by the deploy command path (`bundle_add_cmd.go`), never by `charly box build`/`generate`:
- Once per layer during a pod deploy with `add_candy:` (PodDeployTarget filters to `add_candy:`, OCITarget walks the combined output for overlay synthesis).
- Once per layer during a VM or external deploy (local/k8s/android) — the target walks the combined output.

Pass `HostContext{Target: "host", Distro: ..., GlibcVersion: ...}` for host compilation; zero-value for the pod-overlay container compilation.

Step emission order (mirrors today's `writeCandySteps`):
1. `ShellHookStep` for `env:` + `path_append:` (deterministic map ordering).
2. ONE `SystemPackagesStep` for the image's primary format — resolved via the most-specific-first distro CASCADE over `ResolvedBox.Distro` (e.g. `[ubuntu:24.04, ubuntu]`) plus the layer's top-level `package:` base: packages UNION across every matching per-distro tag section, while `repo`/`copr`/`option`/`exclude`/`module` resolve most-specific-wins. No per-distro section ever shares a mutable format section, so a deb-family repo (trixie vs noble) resolves deterministically. The cascade lives in **ONE shared function `resolveCascadePackages` (`install_build.go`)** called by BOTH the deploy compiler (`compileSystemPackageSteps`) AND the image-build Containerfile emitter (`generate.go writeCandySteps`) — there is exactly one package-resolution path, so a layer's packages are identical whether built into an image or applied at deploy. (Non-primary build formats like `aur` are a separate multi-stage builder concern, not a distro tag, and emit from their own format section.)
3. `OpStep`(s) in YAML order.
4. `BuilderStep`(s) for each matching multi-stage or inline builder.
5. `ServicePackagedStep` / `ServiceCustomStep` from the `service:` list — per-entry routing via `IsPackaged()` + `ServiceSchema.SupportsPackaged`.

`MergePlan([]*InstallPlan, image, addCandies)` composes per-layer plans into a single whole-image plan for target-level walking (sudo batching, single dry-run output).

## The `DeployTarget` interface

```go
type DeployTarget interface {
    Name() string                 // "oci" | "pod" | "host" | "vm:<name>"
    Emit(plans []*InstallPlan, opts EmitOpts) error
}
```

Two in-proc targets implement the bare `DeployTarget` (Name + Emit) interface — `OCITarget` and `PodDeployTarget` — but they are now BUILD ENGINES invoked HOST-SIDE from a lifecycle hook, NOT deploy targets dispatched by `ResolveTarget`. The deploy LIFECYCLE is the separate `UnifiedDeployTarget` interface (Add/Del/Test/Update/Start/Stop/Status/Logs/Shell/Rebuild), and its sole implementer is the generic `externalDeployTarget`: ALL FIVE substrates — `local`, `vm`, `pod`, `k8s`, `android` — route through it over the executor reverse channel, each served by its own out-of-process plugin:

### `OCITarget` (`charly/build_target_oci.go`)
Emits Containerfile text. Consumes `phases.install.container` from the embedded `charly/charly.yml` build vocabulary (falls back to `install_template:`). All compiler-emitted step kinds' build-emit is plugin-served: the plugin-served build-emit kinds (`pluginEmitStepWords` — the PURE C1.1 kinds + the no-op-emit `reboot` (C1.6) + the HOST-COUPLED `system-packages` (C1.2), `builder` (C1.3), `local-pkg-install` (C1.4), `op` (C1.5)) route through `spliceClassStepEmit` to `candy/plugin-installstep`'s `OpEmit` — their former `OCITarget.emit*` methods are gone; the payload is the step VIEW (`stepToView`), and a legitimately-empty render is tolerated (`allowEmpty`; a no-op-emit `apk-install`/`reboot` declares `Emits=false` and is skipped entirely). For the HOST-COUPLED kinds the plugin's `OpEmit` calls back the `step-emit` host-builder over the in-proc reverse channel `spliceClassStepEmit` threads (carrying the box `DistroDef` for SystemPackages + `Generator`/`BuilderConfig`/`Box` for Builder + `ImageBuildDir` for LocalPkgInstall + `ContextRelPrefix` for Op) — the host-engine render is in core TODAY (K3 build-engine migration inventory, not permanent core), so the Op build-emit still delegates to the SAME `Generator.emitTasks` (per-verb emitters `emitCopy`/`emitWrite`/`emitCmd`/`emitMkdirBatch`/...) the box build uses. Only `ExternalPlugin` keeps an in-proc `StepProvider.EmitOCI` — the C1.1–C1.6 externalization is COMPLETE, every InstallStep kind now plugin-served.

Used by: pod deploys with `add_candy:` (overlay Containerfile synthesis) — the ONLY `OCITarget` construction site. `charly box build` / `charly box generate` do NOT use `OCITarget`; build-mode Containerfile emission is the separate `writeCandySteps` → `emitTasks` generator (see the Overview "Build mode is a SEPARATE path").

### `pod` is EXTERNAL (`deploy:pod`, candy/plugin-deploy-pod) — the plugin walks NOTHING; the overlay builds HOST-SIDE
There is no in-proc pod DeployTarget. `pod:` resolves to `externalDeployTarget` (below), served out-of-process by `candy/plugin-deploy-pod`'s `deploy:pod` provider. UNLIKE local/vm, pod does NOT walk the IR on a venue — pod bakes its install steps INTO the image at build time. Its registered `candy/plugin-deploy-pod` lifecycle (M4) (`charly/build_overlay.go`) builds the overlay container image HOST-SIDE in `PrepareVenue` by REQUESTING the uniform F10 `hostBuilders` `overlay` builder (`runOverlayBuild`, C14.3 — the pod-substrate sibling of the `build-resolve` box-build seam `charly box build`/`generate` route through), which runs the RETAINED `PodDeployTarget` (the SAME core `OCITarget`/`Generator` engine, in-process — nothing crosses gRPC, exactly as vm builds its disk host-side): it synthesizes the overlay Containerfile for `add_candy:` (deterministic tag from `(base-image, sorted-layer-set)`, removed on `charly bundle del` unless `--keep-image`), or tags the deploy-name alias when there is no `add_candy:`. `PrepareVenue` no longer constructs `PodDeployTarget` inline — a direct `hostBuilderFor("overlay")` call (no plugin round-trip, since PrepareVenue is already host-side); the serializable `spec.OverlayBuildRequest` carries the scalars while the live plans + nested-venue `ParentExec`/`ParentNode` ride the ctx (a live executor cannot cross the `[]byte` payload). It returns a host-local `ShellExecutor`, so the generic `externalDeployTarget.apply` plugin walk is a clean no-op (the plugin's `Invoke` is a thin acknowledgment) and `recordVenueLedger` no-ops (a pod carries no venue-side ledger — its candies live in the image). The hook also owns the container lifecycle (`charly config`/`start`/`stop`/`status`/`logs`/`shell`; `Rebuild` = `box build`+`check box`+`bundle add`+`stop`+`config`+`start` — the `charly update` R10 fresh-rebuild gate; `PostTeardown` = `charly remove` + drop the `<name>-overlay` images). The bed runner drives a pod bed through the DEFAULT pod path (build → config → start → check-live → `charly remove`) exactly as the in-proc pod did — only `bundle add`'s overlay build internally routes through this hook now.

### `local:` is EXTERNAL (`deploy:local`, candy/plugin-deploy-local) — consumes the IR over the reverse channel
There is no in-proc local DeployTarget. `local:` resolves to `externalDeployTarget` (below), served out-of-process by `candy/plugin-deploy-local`'s `deploy:local` provider (F1). UNLIKE k8s, the local substrate DOES consume the InstallPlan IR: the plugin walks the plan via the shared out-of-process walk (`sdk/kit.WalkPlans`), groups contiguous same-`(Scope, Venue)` steps via `StepsByVenue()`, emits one heredoc per batch, and writes service units (packaged + custom), env.d files, and managed blocks (the host records the returned teardown ops to the ledger via `install_ledger.go`). The plugin owns the walk ORDERING but cannot execute the host-engine step kinds itself — `BuilderStep`, `LocalPkgInstallStep`, `SystemPackagesStep` (host renders via `DistroConfig`), act-verb `OpStep` (host registry `resolveProvisionScript`), and `ExternalPluginStep` (nested plugin dispatch) are driven on the HOST via the `RunHostStep` reverse-channel RPC (the host owns the engine/registry). The host executor is `ShellExecutor` for `host:local`/absent and `SSHExecutor` for `host:<user@machine>`, picked by `rootExecutorForDeployNode` (`charly/deploy_chain.go`). See `/charly-local:local-deploy` for the user-facing surface and `/charly-internals:local-infra` for supporting files (hostdistro, ledger, reverse_ops, shell_profile, builder_run, service_render, deploy_ref).

### `vm` is EXTERNAL (`deploy:vm`, candy/plugin-deploy-vm) — consumes the IR over the reverse channel, INSIDE the guest
There is no in-proc VM DeployTarget. `vm:` resolves to `externalDeployTarget` (below), served out-of-process by `candy/plugin-deploy-vm`'s `deploy:vm` provider — the vm-substrate sibling of `candy/plugin-deploy-local`. UNLIKE k8s, the vm substrate DOES consume the InstallPlan IR: the plugin walks the plan via the SAME shared `sdk/kit.WalkPlans` the local deploy uses. The difference is purely the executor's TRANSPORT — the executor the reverse channel serves for a vm deploy is the **guest `SSHExecutor`**, so the same walk runs INSIDE the guest (shell bodies exec via `ssh guest 'sudo bash -s'`). Plugin-renderable steps (Op/File/ShellHook + the env.d managed-block finalizer/ShellSnippet/Service*/RepoChange) the plugin executes itself via the reverse legs; host-engine steps (`Builder`/`LocalPkgInstall`/`SystemPackages`/act-`Op`/`ExternalPlugin`) AND the `RebootStep` it drives on the HOST via `RunHostStep` (so builders run on the host's podman + artifacts scp into the guest, and the host reboots the guest).

The VM venue lifecycle — boot the domain, build the guest `SSHExecutor` (`kit.WaitForSSH` → `kit.WaitForCloudInit` → `kit.EnsureCharlyInGuest`), return the `VmDeployState` patch, deploy nested `target: pod` children as in-guest quadlets, and teardown — is IMPLEMENTED IN THE PLUGIN `candy/plugin-deploy-vm/lifecycle.go` (`Lifecycle:true`) over `sdk/kit` + `HostBuild("cli")` + the served guest executor. Core keeps ONLY the host-resolved DATA + residual cleanup: the vm `lifecyclePrepareHook` + `lifecyclePostTeardownHook` (`charly/vm_lifecycle_preresolve.go`), consulted GENERICALLY by word through the `grpcSubstrateLifecycle` proxy (`charly/substrate_lifecycle_grpc.go`) that also persists the returned `VmDeployState` via `saveDeployState`. The teardown ledger is keyed HOST-SIDE by `computeDeployID(name)` (like every external deploy); the recorded `ReverseOps` replay over the guest `SSHExecutor` (an `sshReverseRunner`), so teardown runs in the guest.

Used by: `charly bundle add vm:<name> <ref>` / `charly bundle del vm:<name>`. See `/charly-internals:vm-deploy-target` for the full flow, the plugin-implemented venue lifecycle, `VmDeployState` persistence, and SSH-key idempotency.

### k8s is EXTERNAL (`deploy:k8s`, candy/plugin-kube) — NOT an IR-consuming DeployTarget
There is no in-proc k8s DeployTarget. `target: k8s` resolves to `externalDeployTarget` (below), served out-of-process by candy/plugin-kube's `deploy:k8s` provider (F1, beside its `kube:` verb). The Kustomize GENERATION is the COMPILED-IN `candy/plugin-k8sgen` (M13, `verb:k8sgen`/`OpEmit`) — split from the heavy external plugin-kube because the generator has no client-go dep and must resolve in the project-less `from-box` path; the package-main `Capabilities` is NOT crossed (only its 3 scalars Port/UID/GID, alongside `spec.Deploy`/`spec.K8s`, in a `spec.K8sGenInput`), and egress validation (`#K8sObject`/`#Kustomization`) stays HOST-SIDE. `charly/k8s_generate.go` is now a thin SHIM: the host-side `deploy:k8s` preresolver (`charly/k8s_deploy_preresolve.go`) + `charly bundle from-box --target k8s` call `GenerateK8sKustomize`, which Invokes the candy for the manifest docs, validates each via the M16 egress shim (`ValidateEgressValue`), and writes the `base/`+`overlays/` tree under `.opencharly/k8s/<name>/`, shipping the overlay path in `DeployVenue.Substrate` (`spec.K8sDeployVenue`). The plugin then runs `kubectl --context <ctx> apply -k` (the LIVE cluster I/O it owns) and returns the `kubectl delete -k` + tree-removal teardown op the host records. k8s does NOT consume the InstallPlan IR (a k8s deploy compiles no primary image plan). Cluster-specific choices come from a `kind: k8s` cluster template (the `k8s:` entity), not the InstallPlan. See `/charly-kubernetes:kubernetes` + `/charly-internals:plugin`.

### `externalDeployTarget` (`charly/deploy_target_external.go`)
The `UnifiedDeployTarget` adapter for an OUT-OF-PROCESS deploy provider (a `grpcProvider` whose class is `deploy`). The full lifecycle rides over the host-served executor reverse channel — placement-invisible above the registry, so an external deploy substrate is a free authoring choice:

- **Add** marshals the deployment's `InstallPlan`s (as `spec.InstallPlanView`, the JSON-roundtrippable provenance view) into `op.Params` and a `spec.DeployVenue` descriptor into `op.Env`, then `InvokeWithExecutor(OpExecute)` with the host's executor on the go-plugin broker so the plugin runs the deployment's shell/SSH ops on the real venue it cannot hold across the process boundary. It decodes the structured `spec.DeployReply` (`{reverse_ops, record}`) and writes its `ReverseOps` + provenance into the ledger via the SAME `install_ledger.go` path a built-in Add uses. **Before that ledger-persist, `recordDeploy` fills each `ReverseOpPackageRemove.UninstallCmd` from the deploy's `DistroConfig` via `fillReverseUninstallCmds` (`reverse_ops.go`, `t.build.DistroCfg`) — the host renders the format's `uninstall_template` because the out-of-process plugin has no `DistroConfig` (the aur builder's `kit.BuilderReverse` records the op with an EMPTY `UninstallCmd`, deferring to this host render). Both the `local` AND `vm` substrates route through `Add → apply → recordDeploy`, so their aur-builder teardown resolves the `pacman -Rs …` command at `charly bundle del` instead of erroring on an empty command.**
- **Test** runs the deploy-scope checks HOST-SIDE — `runUnifiedTargetChecks` against the executor (the plugin is not involved; the checks are in-proc `CheckVerbProvider`s, R3).
- **Update** re-`Invoke`s `OpExecute` with fresh plans — an idempotent re-Add (the candy's ledger `ReverseOps` are REPLACED, not appended).
- **Del** replays the RECORDED `ReverseOps` from the ledger (no plugin call) via the shared `teardownHostDeploy` — the record-and-replay invariant: only recorded ops are reversed, never recomputed.

The ledger key is `computeDeployID(name, nil, nil)` — derived from the deploy name alone (so the host-venue `Kind()=="host"` never collides with another host-venue deploy on the ledger scan). A bed/deploy that uses an external deploy SUBSTRATE word is recognized at config-PARSE time by the byte-gated, additive declaration pre-scan (`plugin_prescan.go`) before the provider connects; `charly check live` / `charly check <verb>` route an external deploy host-side via the shared `checkLocalTarget` classifier (`check_venue.go`) — the host-venue path the externalized `local:` substrate itself takes (R3). The wire types (`InstallPlanView`, `DeployVenue`, `DeployReply`, `ReverseOp`, `ReverseOpPluginScript`) live in `sdk/spec/deploy_wire.go`, SDK-importable so an out-of-tree deploy plugin constructs the same structs (R3).

## Op selectors at build vs deploy

A provider's `Invoke` carries an `op.Op` selector (`charly/provider.go`). Three drive THIS subsystem (the build/deploy IR), placement-agnostically (in-proc for a builtin, go-plugin gRPC for an external); a fourth, `OpRun`, is the runtime/CLI selector OUTSIDE the install-plan IR (listed here for selector completeness):

- **`OpEmit`** is INVOKED at IMAGE-BUILD time — a `run:` plugin verb / plugin step returns a `spec.EmitReply.Fragment` (with a `spec.BuildEnv` descriptor in `op.Env`) that the generator splices verbatim into the Containerfile (egress-validated). This is a BUILD-mode concern, dispatched from `emitTasks` (`charly/tasks.go`), NOT the IR/`OCITarget` — EXCEPT the pod-overlay `OCITarget`, where `ExternalPluginStep.EmitOCI` (a `class:verb` step) AND `emitExternalStep` (an `external:<word>` `class:step` step declaring `StepContract.Emits=true`, F-STEP-EMIT) both reuse the SAME `invokeOpEmitFragment` seam (R3). A HOST-COUPLED external step's OpEmit calls back the `step-emit` HostBuild builder for a host-engine-rendered fragment. See `/charly-build:generate` + `/charly-internals:generate-source`.
- **`OpResolve`** is ALSO INVOKED at IMAGE-BUILD time — the BUILDER leg, serving BOTH the four DETECTION-builders (pixi/npm/aur/cargo, C10) and the `external_builder:`-selected out-of-tree builders. A `ClassBuilder` provider returns a `spec.BuilderResolveReply` (`{Stage, CopyArtifacts, CopyBinary, InlineFragment}`, with a `spec.BuildEnv` in `op.Env` + a `spec.BuilderResolveInput` render context in `op.Params`): `Stage` (a `FROM <ref> AS <name>` block) splices PRE-main-FROM, `CopyArtifacts`+`CopyBinary` (`COPY --from=<stage> …`) POST-main-FROM, and an INLINE builder's (cargo) `InlineFragment` splices in-candy. The detection builders are dispatched from `emitBuilderStages` / `emitBuilderArtifacts` (the host computes the full render context; the stage template lives in the plugins' `sdk/kit.BuilderResolve`); the `external_builder:` ones from `emitExternalBuilderStages` / `emitExternalBuilderArtifacts` — both share the `resolveBuilderStage` Invoke helper. The multi-stage counterpart of the verb/step `OpEmit` leg. See `/charly-build:generate` + `/charly-internals:generate-source`.
- **`OpExecute`** drives EXTERNAL deploy-context execution over the executor reverse channel — `externalDeployTarget`'s Add/Update `InvokeWithExecutor(OpExecute)` (the deploy-substrate lifecycle), AND an `ExternalPluginStep` on a `local:`/`vm:` deploy walk, which the host executes via the `executeExternalPluginStep` seam (`InvokeWithExecutor(OpExecute)` with the host's live executor, driven over `RunHostStep` as the walk reaches the step) — both decoding the `spec.DeployReply` teardown record (above). `OpExecute` is the deploy-context counterpart of the build-context `OpEmit`: the SAME external verb-step bakes a fragment at build (`OpEmit`) and executes its effect on a live target at deploy (`OpExecute`), picked by venue.
- **`OpRun`** is the RUNTIME / CLI selector, OUTSIDE the install-plan IR (it neither builds an image nor applies a deploy plan): it runs a check verb / live-container probe (`provider_checkenv.go` `invokeVerbProvider`), AND it dispatches an EXTERNAL COMMAND plugin's `charly <word>` subcommand — `provider_command_external.go` `dispatchExternalCommand` forwards the pass-through CLI tokens as `op.Params = {"args":[…]}` (marshalled directly, no `plugin_input` envelope) on an `Invoke(OpRun)` to the lazy-connected out-of-process command provider. Owned by `/charly-internals:plugin` (the command class) + `/charly-check:check` (the verb probes).

## `StepBatch` batching

`InstallPlan.StepsByVenue()` partitions `Steps` into contiguous same-`(Scope, Venue)` runs. The `local:`/`vm:` deploy walk uses this to emit one shell heredoc per batch:

| Batch | Emission form |
|---|---|
| `{ScopeSystem, VenueHostNative}` | `sudo bash <<'CHARLY_ROOT' … CHARLY_ROOT` |
| `{ScopeUser, VenueHostNative}` | `bash <<'CHARLY_USER' … CHARLY_USER` |
| `{_, VenueContainerBuilder}` | `podman run <builder> bash -s < script` |
| `{_, VenueSkip}` | Logged, no exec |

OCITarget doesn't batch — it emits each step in order as Containerfile directives; adjacent same-`USER` steps collapse naturally via the existing `USER` switching logic in `emitTasks`.

## Deferred home resolution (`{{.Home}}` + `InstallPlan.ResolveHome`)

Home-bearing step fields carry the deferred `HomeToken` (`{{.Home}}`) rather
than a home expanded at compile time. `compileShellHookStep` always emits the
token; `compileShellSnippetSteps` emits it for deploy targets (`hostCtx.Target`
== `host`/`vm`) and keeps `img.Home` for the container build. Each
`DeployTarget` calls `plan.ResolveHome(home)` once at emit with the home of the
**actual** destination:

| Target | Home used |
|---|---|
| `OCITarget` (pod-overlay image build) | `img.Home` (the image's runtime home) |
| external `local:` deploy | host home (`ShellExecutor.ResolveHome`) |
| external `vm:` deploy | GUEST home (`SSHExecutor.ResolveHome`) |

`ResolveHome` substitutes the token in `ShellHookStep` (EnvVars + PathAdd),
`ShellSnippetStep` (Snippet + Destination + PathAppend), and `FileStep.Dest`;
it deliberately skips `OpStep` command/content bodies (`~`/`$HOME` there
shell-expand at runtime on the destination as the deploy user) and
`BuilderStep` (home resolved separately by `renderBuilderScript`). It is
idempotent. Baking `img.Home` at compile time was the VM `$HOME` bug: the
synthetic plan's Home was the host operator's, so a guest deploy wrote env.d
pointing at `/home/<operator>` and user-scope installs (npm -g, cargo) landed
in a root-owned path the guest user couldn't write. See
`/charly-internals:vm-deploy-target` "Guest-home resolution".

## `ReverseOp` catalogue

See `/charly-local:local-deploy` for the user-facing reverse-op table. The Go-level source of truth is `ReverseOpKind` in `install_plan.go`; each step's `Reverse()` method emits ops tagged with kind + targets + scope. Execution lives in `charly/reverse_ops.go` — one handler per kind, all routed through `runReverseOps(ops, executor)` in LIFO order.

Adding a new reverse kind requires:
1. Add the `ReverseOpKind` constant in `install_plan.go`.
2. Emit it from the appropriate step's `Reverse()` method.
3. Add a handler function in `reverse_ops.go` and register it in `runReverseOp`'s dispatch switch.

## `EmitOpts` cross-cutting flags

```go
type EmitOpts struct {
    DryRun               bool
    FormatJSON           bool
    AllowRepoChanges     bool
    AllowRootTasks       bool
    WithServices         bool
    SkipIncompatible     bool
    AssumeYes            bool
    Verify               bool
    Pull                 bool
    BuilderImageOverride string
}
```

CLI flags on `BundleAddCmd` / `BundleDelCmd` populate this struct; each target reads what it needs. `AssumeYes` enables all three opt-in gates (via `GateEnabled`).

## Testing

- `install_plan_test.go` — 13 unit tests over step-kind derivations (scope/venue/gate/reverse).
- `install_build_test.go` — 8 integration tests that load real `candy/` via `ScanAllCandyWithConfig`; `testHostContextWithDistro` helper.
- `install_build.go:200` comment — canonical fixture docs.

When you add a step kind, add:
1. A scope/venue/gate/reverse unit test in `install_plan_test.go`.
2. An integration test in `install_build_test.go` exercising the compiler path.
3. Target-specific tests in `build_target_oci_test.go`, the shared out-of-process walk in `sdk/kit/walk_test.go`, and the host-engine channel in `plugin_executor_hoststep_test.go`.

## Cross-References

- `/charly-internals:local-infra` — supporting files (hostdistro, ledger, builder_run, shell_profile, reverse_ops, service_render, deploy_ref)
- `/charly-internals:vm-deploy-target` — the external `vm` deploy (candy/plugin-deploy-vm) + the plugin-implemented venue lifecycle over the `grpcSubstrateLifecycle` proxy + DeployExecutor + SSHExecutor + VmDeployState
- `/charly-internals:vm-spec` — VmSpec shape the vm deploy reads
- `/charly-internals:go` — overall Go code map; Kong CLI framework; mode-purity invariant
- `/charly-internals:generate-source` — Containerfile generation call graph; how OCITarget plugs into Generator
- `/charly-core:deploy` — user-facing `charly bundle add`/`del` surface (host / container / vm: / kubernetes)
- `/charly-local:local-deploy` — host-target user-facing behavior (ledger, gates, ReverseOps)
- `/charly-kubernetes:kubernetes` — K8s-target user-facing behavior (cluster profiles, Kustomize layout)
- `/charly-vm:vm` — VM command family; the vm deploy's venue (`charly vm create`, or auto-booted by the vm deploy plugin's `OpPrepareVenue`, before `charly bundle add vm:...`)
- `/charly-build:build` — build-mode user-facing surface; three-phase template story
- `/charly-image:layer` — charly.yml schema including unified `service:` that map to `ServicePackagedStep` / `ServiceCustomStep`

## When to Use This Skill

**MUST be invoked** when reading or modifying any of `charly/install_plan.go`, `charly/install_build.go`, `charly/build_target_*.go`, `charly/deploy_target_*.go`; when adding a new step kind, target, or reverse-op kind; or when debugging why a particular layer produces a plan that doesn't match expectations. Invoke BEFORE reading the source files or running Explore agents against this subsystem.
