---
name: plugin
description: |
  Use when authoring or modifying a charly PLUGIN — a candy with a `plugin:` block that contributes
  Providers (verbs/kinds/deploy-targets/steps/builders/commands), its own CUE schema, builtin (compiled-in) or
  external (out-of-tree git repo). Covers the unified Provider model, the per-plugin CUE-schema contract
  (single source → Go params for dev + schema-over-Describe RPC for runtime), the SDK, and the loader.
---

# Plugins — the unified Provider + per-plugin CUE-schema model

A **plugin is a candy** (`candy/<name>/charly.yml`) carrying a `plugin:` block. The single addition that
makes a candy a plugin is that block:

```yaml
my-plugin:
  candy:
    version: 2026.180.1200          # mandatory CalVer (any candy)
    description: |-                 # mandatory (ADE)
      What this plugin provides.
    plugin:
      providers: [verb:myprobe]     # "<class>:<word>" — class ∈ kind|verb|deploy|step|builder|command|build
      source: builtin               # OR github.com/org/repo/candy/<name>  (out-of-tree)
      primary:
        myprobe: marker             # scalar sugar target: `myprobe: hello` == {marker: hello}
    plan:
      - check: the myprobe verb dispatches and passes   # ADE: ≥1 deterministic check
        myprobe: { marker: hello }  # the verb sugar — map value = the plugin input verbatim
        context: [runtime]
```

A candy with no `plugin:` block is an ordinary candy; one WITH it is a plugin. Full candy authoring surface
applies (`/charly-image:layer`), including the mandatory `version:`/`description:`/`plan:`+`check:` (ADE).

## One Provider, transport-invisible

Every reserved word — every kind, verb, deploy-target, step, builder, command, build — is served by ONE `Provider`
(`charly/provider.go`): `Reserved() string`, `Class() ProviderClass`, `Invoke(ctx, *Operation) (*Result,
error)`. A Provider is IN-PROCESS (a builtin, registered from `init()`) or OUT-OF-PROCESS (an external,
served over go-plugin gRPC). The registry (`providerRegistry`, `provider_registry.go`), the call sites, and
the bijection gate treat both identically — **the transport is invisible above the registry**. A
`check:` step's authored `<word>: <input>` verb sugar (desugared at parse time to the internal
`plugin`/`plugin_input` pair — authoring that pair directly is a hard load error) dispatches through
`runPluginVerb` → `providerRegistry.ResolveVerb(word)` → `Invoke`, whether the provider is compiled in or
out-of-process. A verb plugin declares its scalar-sugar `primary:` field both in its served capability and
in its candy manifest's `plugin:` block (`primary: {<word>: <field>}`).

**The `build` class (BUILD-ENGINE DISPATCH).** `ClassBuild` serves `build:box` + `build:generate`
(candy/plugin-build, COMPILED-IN): `charly box build` / `charly box generate` route through it instead of
calling `NewGenerator` inline. The plugin's Invoke (op `sdk.OpBuild`) **OWNS the podman DRIVE** (the
build-order loop, per-image build lock via `kit.AcquireImageBuildLock`, `podman build`, push, and the
inline-merge gate) IN the candy — it imports only the sdk module. It reaches the host for what a sdk-only
candy cannot do: the loader + build PREP + the resolved-project ENVELOPE via
`Executor.HostBuild("build-prep", …)` (→ the envelope + a serializable drive-model), the Containerfile
RENDER's host-coupled seams (RenderService, the builder resolves, ValidateEgress, EmitPluginOp, localpkg,
bake-plugins) via `HostBuild("render-seam", …)`. The layer merge is externalized to `verb:oci`
(candy/plugin-oci — no `HostBuild("merge")` seam). `build:box` runs the full drive; `build:generate` calls
`HostBuild("build-prep")` with `GenerateOnly`, renders the Containerfiles itself via `sdk/deploykit.Generator`
(#67 render-DRIVE move — the host no longer renders), and returns the written paths (no podman).
The host-builder KINDS (`build-prep`, `render-seam`, `bake-plugins`) are class-generic action nouns, never the provider
WORDS (the F11 uniform-API gate `TestNoSinglePluginAPISurface` forbids a provider word on that surface). The
Containerfile RENDER DRIVE (`Generate` / `generateContainerfile`) is in `sdk/deploykit` (#67 — driven by
plugin-build over the envelope + the `render-seam` reverse legs); the host keeps ONLY the loader + build-prep +
the resolve-project envelope projection (a kernel M/B Mechanism + the build-prep seam — K3 build-engine
migration INVENTORY, the host render-leg is DELETED). See `/charly-build:build` +
`/charly-build:generate`.

**In-proc reverse channel (compiled-in placement of HostBuild / the reverse channel).** A COMPILED-IN plugin
has no go-plugin broker, so it cannot dial the gRPC reverse channel an out-of-process plugin uses.
`inprocExecutorClient` (`charly/plugin_inproc_reverse.go`) implements `pb.ExecutorServiceClient` by delegating
DIRECTLY to a host-side `executorReverseServer` (no socket); `sdk.NewInProcExecutor` + `sdk.ContextWithExecutor`
thread it onto the Invoke context, and `sdk.ExecutorForInvoke(ctx, brokerID)` (ctx-first, broker-fallback) is
the ONE accessor a plugin's Invoke calls — so the plugin's reverse-channel code is byte-identical compiled-in
vs out-of-process (placement-invisible). It deliberately does NOT reuse `executorInvoker` (which stays
grpcProvider-ONLY — that interface is the discriminator routing external verbs to `ExternalPluginStep`, and a
compiled-in provider must not collide with it); the in-proc reverse channel is threaded by the build dispatch
inline. This is the general foundation the "every builtin routes through the reverse channel" direction needs;
its first consumer is the `build` class.

## Placement: builtin OR external, in-proc OR out-of-process — at deploy AND build time

Placement is a free, per-plugin choice, invisible above the registry: a provider runs EITHER compiled into
`charly` (a builtin, in-process) OR dynamically loaded from an out-of-tree candy (an external, out-of-process
over go-plugin gRPC), and the SAME provider works in either placement with ZERO authoring change. The strategic
direction is that every internal/builtin provider migrates external over time — so author every plugin
placement-agnostic from day one, and design it to work either way.

**Every class is placement-free** — kind, verb, deploy-target, step, builder, AND command are ALL
external-capable. An external (out-of-tree) COMMAND plugin contributes a `charly <word>` CLI subcommand
dispatched OUT-OF-PROCESS: the declared word is prescanned into the Kong grammar before parse, and the provider
is LAZY-connected on the first actual `charly <word>` invocation, which forwards the pass-through args via
`Invoke(OpRun)`. `builtinCommandBase.Invoke` returning "in-process only" is the BUILTIN command path ALONE (a
builtin command contributes via its static `KongCommand()` + Go `Run` handler and never serves itself
out-of-process) — NOT a class-level limit. Each class's leg differs by lifecycle phase: verb/deploy/step/
builder ride build (`OpEmit`/`OpResolve`) and/or deploy (`OpExecute`); command rides CLI invocation (`OpRun`);
a **kind** rides CONFIG LOAD (`OpLoad`) — its serving plugin is recognized + connected at config-PARSE by the
F4 prescan (`registerDeclaredKind` + `connectDeclaredKindPlugins`, re-entrancy-guarded), so a `kind: <word>`
entity whose plugin is NOT compiled in decodes via `runPluginKind` during load. Reference (out-of-process-only):
`candy/plugin-example-kind`; loader mechanism: `/charly-internals:go` (`plugin_prescan.go`).

**A plugin DECLARES its lifecycle PHASE (F9).** Beyond its class, a capability declares a `Phase` (the
`sdk.Phase*` set: `bootstrap → schema → load → build → runtime`, default `runtime`) via
`ProvidedCapability.Phase` over Describe — the ordered point at which the kernel loads/invokes it. The
**`bootstrap`** phase runs BEFORE config validation/migration: the kernel invokes a bootstrap plugin's
`OpBootstrap` on the RAW config bytes (`runBootstrapPhase`, in `LoadUnified` before the schema gate), applying
any transformed bytes it returns — so early-running capabilities (migrate, egress) can themselves be plugins.
Bootstrap plugins are **compiled-in only** (no validated config exists yet to discover an out-of-process
source). Reference: `candy/plugin-example-bootstrap` (a no-op returning the bytes unchanged). M15 (migrate) /
M16 (egress) move those in-core capabilities onto this phase machinery.

**A kind decode is FLAT or STRUCTURAL (F5).** A FLAT kind (the default) lands its `OpLoad` body OPAQUELY in
`uf.PluginKinds[disc][name]` (F4). A STRUCTURAL kind sets `ProvidedCapability.Structural = true` (the proto
`structural` field) in its Describe — its `OpLoad` returns a `spec.Deploy` (BundleNode) MEMBER TREE the host
folds into `uf.Bundle`, the SAME map the in-proc pod/candy decoders populate, so the entity participates in
deploy/check exactly like a builtin (the folded member goes through the SAME `validateDeploy`). This is the
channel that externalizes the structural kind decoders — ALL of them are now DONE: **`group` (C2-group,
candy/plugin-group)**, **the 5 deploy-substrate kinds pod/vm/k8s/local/android (C2-substrate,
candy/plugin-substrate — one provider serving all 5)**, and **the LAST one, the `candy` box⊻layer factory
(C2-candy, candy/plugin-candy-kind)** — all COMPILED-IN. The substrate consumer added the TEMPLATE-map fold
arm: a substrate node in standalone-TEMPLATE shape (a bare `vm:`/`pod:` — no from:/image:, no members) folds
into the typed map `uf.Pod`/`uf.VM`/`uf.K8s`/`uf.Local`/`uf.Android`, alongside the deploy-shape fold into
`uf.Bundle`; candy folds into `uf.Box` (image) / `uf.Candy` (layer). So EVERY authoring kind is plugin-served:
the `#Node` disjunction has ZERO built-in arms (`#Node: {...}` — a structural gate only) and `spec.KindWords`
is EMPTY. (candy's bootstrap-critical box⊻layer routing — candyIsImage + buildCandy — STAYS core: the
discovered-candy pre-check calls it directly, and the COMPILED-IN candy plugin registers at init before any
load, so there is no bootstrap cycle. candy is `Structural:false` — it nests no deploy members — and routes
to the host's foldCandyKind by an explicit disc branch.)

**AUTHORED-member INPUT-threading (the enabler that makes group/substrate externalization real).** A
structural kind's whole POINT is preserving the node's AUTHORED resource-member children (peers, nested
pod-in-pod, cross-member `${HOST:…}` checks) — but they CANNOT ride `op.Params`: that JSON is unified against
the plugin's CLOSED `#<Kind>Input` def, which the member subtree would violate. So the HOST pre-decodes the
authored member children via the SAME core `buildBundleNode` recursion the builtin path uses
(`buildResourceMemberChildren` — ONE member-decode source of truth, R3) and threads the decoded subtree to
`OpLoad` via `op.Env` (`spec.StructuralKindLoadEnv{Members}`). The plugin decodes only its kind-specific scalar
body from `op.Params` and ATTACHES the host-threaded members to its `spec.Deploy` reply — Members for a
targetless kind (group), Children for a workload — so the reconstructed `uf.Bundle` entry is BYTE-EQUIVALENT to
the FORMER builtin `group`'s in-proc decode — the invariant C2-group's `check-group` bed + the
`TestExternalStructKind_StructuralDecode` byte-equivalence test both prove (`${HOST:…}` refs survive as
literals, resolved later by tree position). A
FLAT kind carrying member children is a HARD error (never a silent drop). The parser admits sub-entity children
under a recognized external STRUCTURAL kind (`externalKindMayNestMembers`), core non-resource kinds stay guarded.
Reference (out-of-process-only): `candy/plugin-example-structkind` (decodes deploy-config scalars from
`op.Params`, attaches host-threaded members); the host fold is `runPluginKind` (`/charly-internals:go`); the
byte-equivalence witness is `TestExternalStructKind_StructuralDecode` + the `check-structkind` runtime bed.

**Rich-value variant (C2-substrate + C2-candy — the HOST-pre-decode+ECHO case).** The `op.Params`-decode above
works for a kind whose value is SCALAR-simple (group's `#GroupInput`). The 5 substrate kinds
(pod/vm/k8s/local/android) AND the `candy` box⊻layer factory have a RICH, core-referencing value
(`#Vm`/`#Deploy`/`#LibvirtDomain`/`#Candy`/`#Box`/… with host-canonicalized shorthand like `tunnel:`/`port:`)
that a plugin CANNOT re-decode soundly from `op.Params` nor validate with a self-contained schema. So
candy/plugin-substrate AND candy/plugin-candy-kind use the `spec.StructuralKindLoadEnv.Standalone` channel: the
HOST pre-decodes the WHOLE CANONICAL node via the core loader (`buildBundleNode` deploy / `decodeNodeValue`
template for substrate; `candyIsImage` + `buildCandy` for candy — the bootstrap-critical routing that STAYS
core), validates its value host-side against the KEPT `#<Kind>Value` / `#CandyValue` def
(`validateKindValueCUE`), and threads the canonical result via `op.Env`; the plugin is a PURE ECHO
(`InputDef:""`, no `validateAuthoredPluginInput`), and the host folds the echo into `uf.Bundle` (deploy) / the
typed template map `uf.Pod`/`uf.VM`/… (template) / `uf.Box` (candy-image) / `uf.Candy` (candy-layer).
Byte-equivalence over ALL shapes: `TestSubstrateKind_BothShapesByteEquivalent` +
`TestCandyKind_BothShapesByteEquivalent` (against the direct core decode) + box validate across all repos (candy
is THE core entity) + the `check-substrate` runtime bed. References: `candy/plugin-substrate`,
`candy/plugin-candy-kind` (distinct from `candy/plugin-candy`, the `command:candy` CLI plugin).

**A kind may serve a DEEP `OpValidate` check (F7/C8).** Beyond the static CUE input-def gate the host always
runs (`validateAuthoredPluginInput` — unifies the body against the served `#<Kind>Input`), a kind that sets
`ProvidedCapability.Validates = true` (the proto `validates` field) ALSO serves `OpValidate`: at load, the host
dispatches `Invoke(OpValidate)` with the body, and the plugin returns `spec.Diagnostics` (`{Items: [{Severity,
Message, Path}]}`) — any error-severity item FAILS the load with the messages. Use it for checks CUE cannot
express (cross-field invariants, semantic rules). Reference: `candy/plugin-example-kind` (rejects the sentinel
`marker: INVALID`); dispatch is `runPluginKind` (`/charly-internals:go`).
See "Authoring an external COMMAND plugin" below.

- **The perf invariant that makes placement free.** A builtin dispatches through its typed in-proc fast path
  (`CheckVerbProvider.RunVerb` / `KindProvider.DecodeNode` / `DeployTargetProvider.ResolveTarget` /
  `StepProvider.Emit*`) and NEVER marshals the Op into the serializable `Invoke`
  envelope; the JSON envelope (`marshalJSON`) is paid ONLY out-of-process. Choosing builtin therefore costs no
  envelope tax — placement is a free build/deploy decision, not a performance trade-off. Locked by
  `TestPerfGate_BuiltinVerbsSkipEnvelope` + `BenchmarkVerbTypedDispatchFork` (0-alloc) vs
  `BenchmarkVerbEnvelopeMarshal` (`provider_bench_test.go`).
- **Plugin↔plugin + host-build (F10).** A plugin running WITH a reverse channel (deploy/step/check/build —
  any Invoke the host stands a broker up for) can call BACK to the host to invoke ANOTHER plugin or request a
  host-side build, via the `sdk.Executor`: `InvokeProvider(class, word, op, params, env)` — the host resolves
  the peer in the registry and Invokes it on the caller's behalf (threading the SAME venue executor into an
  out-of-process target over a nested broker — the host is the dispatch broker, since it owns the registry);
  and `HostBuild(kind, spec)` — the host runs the registered host-builder for `kind` — 24 registered kinds
  today. The build/render-relevant ones: `build-prep` (the box-build loader + build-prep + resolved-project
  envelope seam the candy drive calls), `render-seam` (the #67 render's host-coupled seams: RenderService,
  builder resolves, ValidateEgress, EmitPluginOp, localpkg), `bake-plugins` (#67 — bake `bake_plugin:`
  binaries into the final image). The rest: `overlay`
  (the pod overlay build), `step-emit` (host-coupled step fragments), `cli` (run-any-charly-command
  reentry), `hostprobe` (doctor's raw host facts), `feature`, `settings`, `retention`, `plugin-binary`
  (the F10 plugin host build), `vm-build`, `resolved-project`, `validate-project`, `config-resolve` +
  `config-persist`, `deploy-add` + `deploy-config` + `deploy-del` + `deploy-from-box`, `status-substrate`,
  `pod-disposable`, `check-bed`, `check-run`. The build engine is in core TODAY — K3 build-engine
  migration inventory, not permanent core — the box-build podman DRIVE moved to candy/plugin-build in
  P8b, and the Containerfile RENDER DRIVE moved to `sdk/deploykit` (#67, driven by plugin-build over the
  envelope + the `render-seam` reverse legs; the host render-leg is DELETED). This is the shared-capability
  seam: a SHARED plugin (egress, k8s-gen, arbiter) is "a plugin others invoke", never "kept in core".
  Reference: `candy/plugin-example-dispatch`; mechanism: `/charly-internals:install-plan`
  (`plugin_dispatch_reverse.go`).
- **Deploy time.** An external deploy-target provider runs its full Add/Test/Update/Del lifecycle over the
  host-served executor reverse channel — the plugin applies the deployment's ops on the real venue it cannot
  hold across the process boundary (`OpExecute`), and the host records the returned teardown ops to the ledger.
  A bed/deploy that uses an external deploy SUBSTRATE word is recognized at config-PARSE time (before the
  provider connects) and routed host-side by the shared check classifier. **A substrate may ALSO bring its OWN
  host-side venue LIFECYCLE + PRERESOLVE (F6):** a `class:deploy` capability declaring `Lifecycle=true` gets a
  wire-backed `substrateLifecycle` registered at plugin-load — the host calls its `OpPrepareVenue`/`OpStart`/
  `OpStop`/`OpStatus`/`OpRebuild`/… (host→plugin on `Provider.Invoke`), and `OpPrepareVenue` returns a
  `spec.VenueDescriptor` the host re-materializes into a real executor (the live executor never crosses the
  wire). One declaring `Preresolve=true` gets a wire-backed `deployPreresolver` (`OpPreresolve` → the opaque
  `DeployVenue.Substrate` payload), generalizing the in-core k8s/android preresolvers. Reference
  (out-of-process-only): `candy/plugin-example-lifecycle`; mechanism: `/charly-internals:install-plan`
  (`substrate_lifecycle_grpc.go`). This is the channel M4 reuses to externalize the pod/vm lifecycles. An external **`run:` plugin verb /
  step** composed INSIDE a deploy (a `local:`/`vm:` target, where the install runs ON the target, not baked
  into an image) likewise EXECUTES at deploy: it lowers to an `ExternalPluginStep` IR node which the external
  `local:`/`vm:` deploy walk reaches as a host-engine step over `RunHostStep`, where `executeExternalPluginStep`
  `Invoke(OpExecute)`s WITH the live `DeployExecutor` on the SAME reverse channel, so the plugin runs
  its deploy-context effect on the target and RETURNS its teardown `ReverseOp`s, which the host records to
  the ledger and replays at `charly bundle del` (record-and-replay, the SAME `spec.DeployReply` wire as the
  deploy target — R3). Only an EXTERNAL provider is routed there (the `executorInvoker` discriminator,
  satisfied SOLELY by the out-of-process `grpcProvider`); a builtin `ProvisionActor` verb keeps its in-proc
  shell path. So the verb/step class is external-capable at BOTH build (`OpEmit`, next bullet) AND deploy
  (`OpExecute`), placement-agnostic. Detail → `/charly-internals:install-plan` (the `externalDeployTarget`
  lifecycle + the `ExternalPluginStep` IR kind + the `OpExecute` reverse channel).
- **Build time.** `charly box build` / `charly box generate` connect the project's external plugin candies during
  image generation, so a plugin EXECUTES at build to emit its Containerfile contribution, placement-agnostically
  (a builtin in-proc, an external over gRPC) — and BOTH the verb/step leg AND the builder leg ride the SAME
  connect seam, class-agnostically:
  - a `run:` plugin **verb / step** returns a Containerfile fragment via `OpEmit` → `spec.EmitReply.Fragment`,
    spliced verbatim into the Containerfile (egress-validated).
  - a **builder** (`ClassBuilder`) returns a multi-stage build via `Invoke(OpResolve)` → `spec.BuilderResolveReply`:
    its `Stage` (a `FROM <ref> AS <name>` block) is spliced PRE-main-FROM, its `CopyArtifacts`+`CopyBinary`
    (`COPY --from=<stage> …`) POST-main-FROM, and an INLINE builder's `InlineFragment` in-candy. This serves BOTH
    the four DETECTION-builders (pixi/npm/aur/cargo — selected by a candy's detect files, rendered via the shared
    `sdk/kit.BuilderResolve`, C10) AND an out-of-tree builder a candy selects with `external_builder: <word>`.
    This is the build-time BUILDER leg — the multi-stage counterpart of the verb/step OpEmit leg, so `builder` is an
    external-capable class at build too (alongside verb/kind/deploy/step). The `command` class has no build-time
    leg — a command dispatches at CLI invocation, not at build — and is external-capable THERE via `Invoke(OpRun)`
    (the Placement paragraph above), so EVERY class (kind/verb/deploy/step/builder/command) is external-capable.
  This is operator-authorized build-time execution of host-built plugin code: a project's composed external
  plugins run as host code during its image builds. Detail → `/charly-build:generate` + `/charly-internals:generate-source`.

## The per-plugin CUE schema — the single source, two consumers

**Every plugin WITH authored input ships its OWN `.cue` schema, and it is the SINGLE SOURCE for that
plugin's params.** This is CLAUDE.md's "Schema Driven Design (SDD)" pillar applied per-plugin: the schema
comes BEFORE the plugin's code, and both consumers below are derived from that one source (the
cross-generator pipeline map + the generation-coverage current state live in `/charly-internals:go`
"Schema Driven Design (SDD)"). An INPUT-LESS plugin (no `input_def` on any capability) ships NO schema —
the load gate waives it (the former requirement forced dozens of near-identical stub files). The schema is
SELF-CONTAINED (package-less, references no base def) and used two ways — the SAME contract core `spec` uses:

1. **DEV-TIME → Go params.** `cue exp gengotypes` (driven by `task cue:gen`, which wraps the schema with
   `package params` + `@go(params)`) emits the plugin's `params/cue_types_gen.go`. The provider decodes
   `plugin_input` into that TYPED struct — never a hand-parsed `map[string]any`, never a hand-written struct.
2. **RUNTIME → schema-over-RPC.** The plugin SERVES its `.cue` source over the Provider **`Describe`**
   channel (the proto `Capabilities.schema_cue` field + structured `ProvidedCapability{class,word,input_def}`).
   The host splices it onto charly's base schema (`base ++ plugin`, via the public `sdk/schemaconcat` — the SAME
   concat contract as the runtime `sharedCueSchema`, R3) and validates every authored verb input (the
   desugared internal `plugin_input`) against the plugin's def (e.g. `#MyprobeInput`). The host **never reads a candy's `schema/` dir from disk** — the
   schema travels WITH the plugin.

**A `class:step` plugin ALSO declares its install-step contract over Describe (F3).** A step plugin (a
PLUGIN-contributed install-step KIND, distinct from a `class:verb` step which rides the fixed
`ExternalPlugin` kind) sets `ProvidedCapability.StepContract{Scope,Venue,Gate,Emits}` (the proto
`step_contract` field; `sdk.ProvidedCapability.StepContract`) — the host carries that DECLARED contract so
a `run:` step carrying the word's `<word>: <input>` sugar lowers to an `externalStep` (kind
`external:<word>`, opaque Payload) the OPEN DEFAULT ARM dispatches via `OpExecute`, with NO compiled-in case. Reverse is NOT declared (an external
step's teardown ops are recorded dynamically from its `OpExecute` reply). **BUILD leg (F-STEP-EMIT):**
`StepContract.Emits=true` declares the step ALSO produces a build-context Containerfile FRAGMENT — served by
`Invoke(OpEmit)` → `spec.EmitReply.Fragment`. Composed into a POD overlay (add_candy), the pod-overlay
`deploykit.OCITarget` (in the candy `plugin-deploy-pod`) reaches the host's open external-step arm
(`ociEmitStep`, over `HostBuild("step-emit","oci-emit-step")`) which Invokes that OpEmit and splices the fragment (`Emits=false` → a
deploy-only step, skipped on the image build, like apk); a HOST-COUPLED step's OpEmit calls back
`HostBuild("step-emit", …)` for a host-engine-rendered fragment. A step plugin serving OpEmit is a PURE
step (self-contained fragment); the reference `candy/plugin-example-stepkind` serves BOTH legs (OpExecute at
deploy, OpEmit at build). A `class:step` plugin may ALSO serve ONLY the build-emit leg: the compiled-in
`candy/plugin-installstep` serves `OpEmit` for the compiler-emitted builtin InstallStep kinds, fed the
compiler-produced step VIEW as payload — those kinds keep their typed IR + `kit.WalkPlans` deploy leg
(so the plugin needs no `OpExecute`); the host routes them by `pluginEmitStepWords`, not the
`external:<word>` arm. Two sub-categories: the PURE kinds
(file/shell-hook/shell-snippet/service-packaged/service-custom/repo-change/apk-install, C1.1; + the
no-op-emit reboot, C1.6 — `apk-install`/`reboot` declare `Emits=false` and are skipped at build) format
their fragment directly from the view; the HOST-COUPLED `system-packages` (C1.2) + `builder` (C1.3) +
`local-pkg-install` (C1.4) + `op` (C1.5) kinds instead call back `HostBuild("step-emit", …)` (echoing the returned
`EmitReply`) because their render needs the host build engine (`system-packages`: DistroDef format templates;
`builder`: the multi-stage `buildStageContext` + `RenderTemplate` engine; `local-pkg-install` is DIFFERENT
(W3) — its render `deploykit.RenderLocalPkgImageInstall` is a PURE sdk/deploykit function needing no host
callback, routed through this seam only for `buildEngineContext` threading uniformity; `op`: the RICHEST — `Generator.emitTasks`, the
full per-verb render pipeline with COPY staging + op coalescing). Authoring + IR mechanism: `/charly-internals:install-plan` (the
`externalStep` row + the build-emit externalization note); reference: `candy/plugin-example-stepkind`,
`candy/plugin-installstep`.

**Zero builtin/external distinction in schema handling.** Both arrive at the host as a `PluginUnit`
(`Providers` + `Schema`) from `PluginTransport.Connect` — `InProcTransport` for a builtin, `LocalTransport`
(go-plugin exec) for an external. The host's load/gate/validate code NEVER branches on which kind it is. The
only difference is WHERE the plugin runs (compiled into charly vs a separate process), and therefore WHEN its
providers register (a builtin at `init()`, an external at deploy/check load) — a load-TIMING property, never a
schema-handling one.

### The load gate + the validator (one each, shared)

- `registerPluginUnitSchema(name, schema)` is THE load gate (`plugin_loader.go`), byte-identical for builtin
  and external: it rejects a schema that will not **splice** onto the base, a declared `input_def` the
  schema does not define, and an EMPTY schema from a plugin that DOES declare input defs — all LOUD failures
  at load. An input-less plugin (no `input_def` on any capability) legitimately serves NO schema and passes
  the gate. Builtins are gated at process start (`loadBuiltinPluginUnits`, a `sync.Once` pass over every
  registered unit); externals at connect (`loadPluginUnit` → build on host → `LocalTransport.Connect` →
  gate → register).
- `validateAuthoredPluginInput(class, word, json)` is THE validator: it looks the def up in the process-wide
  `pluginSchemas` set (filled by the gate) and unifies the authored input against it. Wired into
  `runPluginVerb` before dispatch — a missing/empty/typo'd field is a hard `TestFail`, not a silent surprise.

## The retired in-charly-module builtin path

There is NO LONGER an "in-charly-module builtin" path — a Provider whose Go lived under the charly
module's former `plugin/builtins/<name>/` subtree and registered from `package main`'s `init()` via
`RegisterBuiltinPluginUnit`. It was retired as each builtin relocated into a candy: that
subtree is GONE, and the last unit, `examplerunverb`, is now the compiled-in
kit candy `candy/plugin-examplerunverb/` (guarded by `charly/plugin_examplerunverb_relocated_test.go`).
The `source: builtin` candy-linkage form is likewise gone (exampleprobe is a real candy module).

Every builtin today is ONE of the two CANDY forms below — a candy COMPILED IN via `compiled_plugins:`
("Authoring a COMPILED-IN plugin candy") or a HOST-COUPLED check-verb KIT candy ("Authoring a
HOST-COUPLED check-verb candy"). Author new builtins as one of those; there is no in-charly-module
builtins subtree to mirror.

## Authoring an EXTERNAL plugin (out-of-tree git repo)

The candy IS its own Go module — its `go.mod` carries `require github.com/opencharly/sdk v0.0.0`
plus, while in-repo, `replace github.com/opencharly/sdk => ../../sdk`; a PUBLISHED out-of-tree module
drops the replace and requires a TAGGED `github.com/opencharly/sdk` instead (tag scheme
`v0.<YYYYDDD>.<HHMM leading-zeros-stripped>`, e.g. superproject `v2026.185.0751` ⇄ sdk `v0.2026185.751` —
the superproject's own `vYYYY.DDD.HHMM` tags are not valid Go module versions). A plugin module imports
ONLY the sdk module, never charly core. Mirror `candy/plugin-example-external/`:

- `schema/<name>.cue` — the self-contained def (same shape as a builtin's).
- `params/cue_types_gen.go` — generated the same way (the gen loop also covers the in-repo example).
- `main.go` — `func main() { sdk.Serve(&provider{}, &meta{}) }`; the provider decodes `plugin_input` into the
  generated `params.<Word>Input`; `meta.Describe` returns `sdk.BuildCapabilities(calver, []sdk.ProvidedCapability{…},
  schemaFS, "schema")` (it `//go:embed`s `schema/*.cue`). `BuildCapabilities` concatenates + compiles the
  schema STANDALONE (failing loudly before serving) and ships the source in `schema_cue`.
- The candy's `plugin.source` is the `github.com/org/repo/candy/<name>` ref. charly's loader fetches the repo
  (the same `@github` resolver candies use), `go build`s the provider binary ON THE HOST, and connects
  out-of-process via `LocalTransport`. The host build runs with `GOWORK=off` so a repo-root `go.work` cannot
  reject a non-member candy dir — the out-of-process build is always standalone in the candy's own module.

## Authoring a COMPILED-IN plugin candy (the candy compiled INTO charly)

The SAME out-of-tree candy can be COMPILED INTO charly — the in-proc placement of a candy, selected
per-charly-build by `charly.yml` `compiled_plugins:`. This ships a plugin candy INSIDE the binary
WITHOUT its Go living in charly's module (it rides `go.work`). `candy/plugin-example-external/` is the
reference: it is BOTH the out-of-process example above AND the compiled-in example — one provider, two
placements, ZERO authoring change.

- The provider lives in the candy's IMPORTABLE root package (`NewProvider() pb.ProviderServer` +
  `NewMeta() pb.PluginMetaServer` + `//go:embed schema/*.cue`), NOT `package main`. `main.go` moves to
  `cmd/serve/` as a 3-line `sdk.Serve(<pkg>.NewProvider(), <pkg>.NewMeta())` shim (the out-of-process
  entrypoint, host-built only when the candy is NOT compiled in).
- List the candy in `compiled_plugins:` (the embedded `charly/charly.yml` for the default binary; a
  consumer's own `charly.yml` for a custom footprint — "which plugins are in the binary" is a normal
  candy-inclusion choice).
- `pluginsgen` (`charly/internal/pluginsgen`, run by `task build:binary` before `go build`, `GOWORK=off`,
  stdlib+yaml only) reads `compiled_plugins:` and emits `charly/plugins_generated.go` (one
  `registerCompiledPlugin(<pkg>.NewProvider(), <pkg>.NewMeta())` per candy) + the repo-root `go.work`
  (`use ./charly` + `use ./sdk` + a `use ./candy/<name>` per candy, so `go build ./charly` resolves the
  candy imports; pluginsgen guards a missing sdk submodule with a clear `git submodule update --init sdk`
  error). Both are COMMITTED + reproducibility-gated (`TestPluginsGenReproducible`).
- `registerCompiledPlugin` drives `InProcServedTransport`: it calls the candy's `Describe` IN-PROCESS, runs
  the SAME `buildUnit` capability-lift + schema gate an external goes through (so the compiled-in schema
  enters the SAME `loadBuiltinPluginUnits` gate), and registers each capability wrapped in an
  `inprocProvider` (origin `"builtin"`) — the in-proc twin of `grpcProvider`. Dispatch is registry-routed,
  transport-invisible.
- COEXIST: a candy compiled in (origin `"builtin"`) is SKIPPED by `loadProjectPlugins` (the out-of-process
  host build is redundant); a candy NOT in `compiled_plugins:` still host-builds + connects out-of-process
  when a plan references its word. Placement is a per-charly-build choice, invisible above the registry.
- PERF: a compiled-in pb CANDY dispatches through the pb `Invoke` envelope IN-PROCESS (no socket) via
  `inprocProvider`, whereas a HOST-COUPLED KIT candy (next section) uses its typed fast path
  (`RunVerb`/`DecodeNode`, no envelope). The pb-candy path pays the JSON envelope but not the gRPC transport.

## Authoring a HOST-COUPLED check-verb candy (the kit — dual-placement via the reverse channel)

A check verb whose logic needs the LIVE check engine — exec-in-container, host-vantage HTTP, host TCP
dial (`file`/`http`/`port`/`command`/`service`/…) — implements **`sdk/kit`**, the importable
contract for the check engine. It runs in EITHER placement, invisibly above the registry: COMPILED-IN
(charly passes the live `*Runner` as the `kit.CheckContext`) OR OUT-OF-PROCESS (the CheckContext legs are
served back over the host's reverse channel — ExecutorService for `cc.Exec()` + CheckContextService for
`cc.HTTPDo`/`cc.AddBackground`, F2 — while the scalar legs `Mode`/`Box`/`Instance`/`Distros`/`DialTimeout`
ride the env_json snapshot). `candy/plugin-port` + `candy/plugin-http` are the reference (both served
OUT-OF-PROCESS in the default build); the remaining kit candies are compiled-in by default until M1 adds
their `cmd/serve` shim. Shape:

- The candy's importable root package implements `kit.CheckVerbProvider` (`Reserved()` + `RunVerb(ctx,
  cc kit.CheckContext, op *spec.Op) kit.Result`) — the verb's logic (formerly the `r.runX` *Runner
  method) lives HERE, reaching the deployment through `cc.Exec().RunCapture` / `cc.Mode()` /
  `cc.DialTimeout()` / `cc.HTTPDo(...)` / `cc.Distros()`. It exports `NewCheckVerb() kit.CheckVerbProvider`
  + the raw schema `embed.FS` (`SchemaFS` + `SchemaDir`) + `InputDefs`.
- COMPILED-IN: charly's `registerCompiledCheckVerb` (generated into `plugins_generated.go` by pluginsgen,
  which detects the kit shape by the exported `NewCheckVerb`) wraps it in a `kitVerbAdapter` (a package-main
  `CheckVerbProvider` that passes the live `*Runner` as a `kit.CheckContext` via `runnerCheckContext` and
  converts `kit.Result`→`CheckResult`), concatenates the candy's schema (via the public
  `sdk/schemaconcat`), and registers through the SAME `RegisterBuiltinPluginUnit` gate (origin
  `"builtin"`). Dispatch is the SAME `runOne`→`CheckVerbProvider.RunVerb` path a compiled-in candy verb
  uses — full typed fast path, the real `*Runner`, no envelope.
- OUT-OF-PROCESS: a `cmd/serve/main.go` shim calls `sdk.ServeCheckVerb(pkg.NewCheckVerb(), calver,
  pkg.SchemaFS, pkg.SchemaDir, pkg.InputDefs)`, which wraps the kit verb in a pb.ProviderServer whose Invoke
  reconstructs a `sdkCheckContext` from the InvokeRequest broker (ExecutorService + CheckContextService) +
  the env_json snapshot, then runs `RunVerb`. The host go-builds `./cmd/serve` + connects via
  `LocalTransport` when the candy is NOT in `compiled_plugins`; `invokeVerbProvider` (provider_checkenv.go)
  serves BOTH reverse services on one broker id. The verdict round-trips as the same `{status,message}`
  every out-of-process verb returns.
- `kit` imports only the stdlib + `sdk/spec`; the candy imports `kit` + `sdk` + `spec` + its `params`.

A kit candy keeps the verb's logic (RunVerb on `kit.CheckContext`) OUTSIDE charly's module while preserving
the typed fast path — runnable in-proc (compiled-in, the real `*Runner`, no envelope) OR out-of-process (the
reverse channel) with ZERO authoring change.

The SDK module (`github.com/opencharly/sdk`) is the ONLY module a plugin imports — root package
`sdk` (`Serve`, `ServeCheckVerb` (the kit-verb out-of-process serve entry), `Handshake`,
`BuildCapabilities`, `ProvidedCapability`, `Conn`, plus the shared out-of-process check-verb helpers
`ResultJSON` (the `{status,message}` reply) / `CheckRequiredModifiers` (the required-modifier check) +
the `*Executor` venue methods `VenueCapture`/`VenueHasTool`/`VenueRunSilent`), `sdk/kit` (the
pure-helper package, stdlib + `sdk/spec` only — `ShellQuote`, `TrimPreview`, `MethodSpec`,
`WalkPlans`, …; the SDK root imports it too), `sdk/spec`, and `sdk/proto`. `schemaconcat` is the
public `sdk/schemaconcat` package (the SDK uses it internally).

## Authoring an external COMMAND plugin (a `charly <word>` subcommand)

A `command:<word>` provider is an external plugin (authored exactly like the verb-class one above — its own Go
module, self-contained `schema/<name>.cue`, generated `params/`, `sdk.Serve` + `BuildCapabilities`) that
contributes a TOP-LEVEL `charly <word>` CLI subcommand. Mirror `candy/plugin-example-command/`:

- `plugin.providers: [command:<word>]` + `source: github.com/org/repo/candy/<name>` in the candy's `plugin:`
  block; `Describe` returns the capability with `Class: "command", Word: "<word>"`.
- `Invoke` handles `OpRun` (the command-run selector): the host forwards the user's pass-through CLI tokens
  from `charly <word> <args…>` as `op.Params = {"args": [...]}` marshalled DIRECTLY — NOT wrapped in the
  `plugin_input` envelope a verb CHECK step uses. The provider decodes that into its generated typed params
  struct (e.g. `params.<Word>Input` with an `Args []string` field) and does its effect.

The discovery → grammar → dispatch flow (host side, owned by `charly/plugin_command_prescan.go` +
`provider_command_external.go`): when the candy is discovered in the project, a byte-gated prescan
(`prescanProjectCommandWords`, run in `main` BEFORE `kong.Parse`) registers the declared word so `charly <word>`
PARSES; `collectExternalCommandPlugins` builds a Kong grammar holder for it with the provider UNconnected. The
host build + gRPC connect is LAZY — paid ONLY when the user actually runs the command: `dispatchExternalCommand`
calls `connectCommandPlugin` (scoped to the one word) then `Invoke(OpRun, {"args":[…]})`. So every `charly`
invocation that is NOT `charly <word>` is byte-for-byte unaffected. (A builtin command, by contrast, contributes
via its compiled-in `CommandProvider.KongCommand()` + Go `Run` handler — `provider_command.go`.)

**A command candy can ALSO be COMPILED IN (F8) — placement-invisible like every other class.** List its candy
in `compiled_plugins:` and it registers in-proc (an `inprocProvider`, Class command); the host builds the SAME
dynamic Kong grammar (`externalCommandHolder`, pass-through `Args`) and `dispatchCommand` routes it IN-PROC via
`Invoke(OpRun)` (`dispatchInProcCommand`) instead of `syscall.Exec` — the candy's `Invoke(OpRun)` handler runs in
charly's own process (native stdio/TTY). So author a command candy DUAL-PLACEMENT: an importable provider
package (`NewProvider`/`NewMeta`, `Invoke(OpRun)` runs the effect, `Describe` advertises `command:<word>`) + a
`cmd/serve` `sdk.Main(..., CliMain)` shim for the out-of-process path, both calling ONE shared effect (mirror
`candy/plugin-example-command`). This is the command half of compile-in-for-all-six-classes; the M-series moves
the dedicated builtin commands into candies on this surface.

## Why self-contained schemas

A plugin's `#<Word>Input` references NO base def, so it compiles STANDALONE — the exact property
`cue exp gengotypes` needs to generate Go params, AND the property that lets the SDK compile it serve-side.
The host's `base ++ plugin` splice therefore exists to detect a def-name **collision** with the base, not to
resolve base references. (`TestExternalSchemaSelfContained` proves a base-referencing schema fails a standalone
compile.)

## The kernel/plugin boundary law — what belongs in the kernel vs a plugin

This is the authoritative detail for CLAUDE.md's **"The kernel/plugin boundary law"** pillar. It decides,
uniformly and with NO per-kind exception, whether any schema / typed shape / validation / behaviour is
KERNEL (`charly/` core + `sdk/`) or PLUGIN. Read it before adding or placing any capability.

**The law.** The kernel is a **kind-blind execution substrate**: a construct is KERNEL iff it is one of
four kind-AGNOSTIC things —

- **(E) Envelope** — a generic carrier or the reserved vocab naming its slots: `#Node`(arm-less) /
  `#Step` / `#Op` / the `#Deploy` tree / the `InstallPlan` IR / `#Context`, and the wire replies plugins
  resolve into (`VenueDescriptor`, `EmitReply`, `BuilderResolveReply`, `DeployVenue`, `StepEmitRequest`,
  the opaque `Substrate json.RawMessage`). Carries opaque, word-tagged payloads; encodes no kind.
- **(M) Mechanism** — a generic engine that transports / renders / validates / re-materializes an
  envelope, dispatched **by word against a data table, never branching on a concrete kind** — and the
  ONLY M-mechanisms that live in `charly/` are plugin loading (the provider registry + transports +
  reverse-channel legs), prescan-dispatch, the kind-decode MATERIALIZE (folding plugin-parsed config
  into the typed project view — the dispatch half of loading), and the wire broker. Every OTHER
  kind-blind mechanism (parse, render, resolve, walk, engine) lives in an sdk KIT consumed by plugins:
  the config PARSE is `sdk/loaderkit` (plugin-served via the `DocParser` seam); the build engine, the
  deploy walk, the CUE-unify check, and the ledger currently in `charly/` are TRACKED MIGRATION
  INVENTORY with named K-wave exits (K3/K4/K5), never permanent M-residue. Canonical illustration:
  `loaderkit.ParseDoc` stays kind-blind by reading the `loaderkit.Threaded` kind-recognition snapshot
  — clause-D DATA threaded to a kind-blind mechanism, not a registry query. A kind-blind mechanism
  reached THROUGH a seam (a reshaper, the migration op-walker) is itself a PLUGIN/sdk-lib, NOT core.
- **(B) Bootstrap** — the single irreducible root that must exist before any plugin can load: the
  `candy`⊻`box` factory (`candyIsImage`+`buildCandy`) + the provider-registry seed. It cannot be a
  plugin without a bootstrap cycle (the discovered-candy pre-check calls it directly).
- **(D) Data-not-code** — a kind-recognition fact (which words are kinds / nest members / validate
  against which value-def) loaded from CUE/config and consulted by word: the CUE-derived vocab
  (`spec.OpVerbs`/`StepKeywords`/`DocDirectives`/`ResourceKinds`), the schema-version consts, the
  `#Migration` grammar, and the canonical example — `loaderkit.Threaded`, the 4-map DATA SNAPSHOT the
  host fills from the registry BEFORE the kind-blind parse (untying the loader↔registry cycle at zero
  abstraction cost — DATA threaded to a kind-blind mechanism, never a live registry query in the
  parse). NEVER a compiled-in per-kind Go branch or map.

- **(R) Resolve-to-envelope — the DEFAULT.** Everything else — a kind's schema, typed Go shape,
  deep-validation def, render/behaviour, and produced artifact — is a PLUGIN. It reaches the kernel only
  by **resolving** its config into an E-envelope that a Mechanism consumes.

**The decision procedure.** For any construct ask: generic Envelope (E)? a kind-blind Mechanism that is
plugin loading / dispatch / the kind-decode materialize / the wire broker (M — nothing else in core)?
the Bootstrap root (B)? kind-recognition Data (D)? If none → it is a plugin (R). Placement
is decided ONLY by this test; **difficulty NEVER enters it** (CLAUDE.md forbidden-excuse catalog) — a
thing stays kernel only because it is E/M/B/D, never because moving it is hard.

**The un-gameable self-test — the "incomplete seam".** The four kernel escapes are each kind-AGNOSTIC and
may never name a concrete kind in code. So a kernel `import` of a `spec.<Kind>` struct read for its
fields, a `switch` on a kind word, or a per-kind Go map is BY DEFINITION an R-item that leaked — an
**incomplete seam: a bug fixed immediately (one R10-gated cutover each), never a kept exception, never
parked as a "remaining candidate."** Those three tells are what you grep for.

**The named trap — "host-boundary object" is never a permanence reason.** Calling a construct a
"host-boundary object" — it "can't cross the process boundary," "drives podman/ssh/flock/systemd itself,"
or fits "the P8/P10 pattern" — is NEVER grounds to keep it in core. A plugin runs on the SAME host and
drives that object itself (exactly as `candy/plugin-vm` and `candy/plugin-kube` already do), or reaches a
live venue through the reverse-channel broker (M4, the `substrateLifecycle`/`ExecutorService` legs) —
needing the broker or the host IS the whole point of that seam, never a reason the construct must stay
core.

**The defines-vs-calls test — the concrete grep that makes E/M/B/D un-mis-applicable.** To decide whether
a file is a genuine M-mechanism (kernel) or an R-item (moves), grep for where the mechanism is DEFINED —
the registry in `provider_registry.go`, the kind-decode fold in `materialize.go`, the reverse-channel
broker/`InvokeProvider` in `plugin_inproc*.go`/`plugin_dispatch_reverse.go`. A file that only CALLS one of
those — dispatches through `providerRegistry.ResolveVerb`, composes a live executor, reads resolved
config — is a CAPABILITY that USES the mechanism, not the mechanism itself: an R-item, it moves. **A
capability that uses M1–M4 is not thereby M1–M4.**

**Alias-is-always-residue — an alias is NEVER permanent, regardless of what it aliases.** A `type X =
spec.X` / `var y = spec.Y` re-export in `charly/` is ALWAYS an R-item under the ZERO-ALIASES v2 target,
REGARDLESS of what it aliases — even a genuine E-envelope type. The alias is not "permanent because it's
an E-type"; the alias IS the mislocated call site, the whole point of ZERO-ALIASES. Classify every
`charly/*_aliases.go` (and stray `_alias.go`) entry as residue: delete it and repoint its callers to
`spec.*` (or the owning kit) directly. Motivating incident: an auditor counted `labels.go`'s `BoxMetadata =
spec.BoxMetadata` alias and `install_plan.go`'s `Scope`/`Venue`/`Phase` aliases (all grep-verified genuine
`spec.*` E-types) as "permanent E," then self-corrected — an alias's TARGET being E doesn't make the alias
itself permanent.

**A concrete kind's typed shape is R, not E.** The (E) envelope bucket is ONLY kind-AGNOSTIC carriers —
`InstallPlan`, `VenueDescriptor`, `#Node`/`#Step`/`#Op`, the wire replies. A struct NAMED after a concrete
kind, with kind-specific fields and accessors — `Candy`, `VmSpec`, `ResolvedBox` — is that kind's TYPED
SHAPE: an R-item, moving to its owning kit/plugin (`Candy` → `sdk/buildkit`, alongside the
already-relocated `ResolvedBox`). "Carries data" is not the E test; kind-AGNOSTIC is. Motivating incident:
an auditor counted `layers.go`'s `Candy` struct (grep-verified: 60+ accessor methods, every one
kind-specific) as E because it "carries data," then self-corrected.

**The practical audit framing — invert the default.** Every file is an R-item (it moves to a plugin)
UNLESS it is LITERALLY one of the tiny kernel whitelist: the four in-core M-mechanisms (plugin loading /
prescan-dispatch / kind-decode materialize / the wire broker), the B bootstrap root, D kind-recognition
data, or an E generic envelope. Auditing a cone by asking "is this hard to move" instead of "is this one
of E/M/B/D" is the exact failure this framing forecloses: the bed runner, the check/ADE harness, the build
engine, the deploy walk, and the VM engine are ALL R-items (the v2 ledger already names them plugins) —
none of them earns kernel status by being awkward to relocate. Motivating incident: two auditors
independently mis-classified the deploy + check cones as ~90% permanent using exactly the
"host-boundary/gather-engine" excuse; the true kernel in those cones is ~0.3%.

**The canonical shape every kind copies — resolve-to-envelope.** `builder` is the reference: its plugin
serves its own `#BuilderInput` schema, decodes into its own params, validates its own input, and RESOLVES
via `Invoke(OpResolve)` → `spec.BuilderResolveReply` (`Stage`/`CopyArtifacts`/`InlineFragment`); the build
engine splices the generic fragment and never imports a builder struct. Every concrete kind reaches the
kernel the same way — a distro resolves to install/phase/localpkg fragments, a substrate to a
`VenueDescriptor` + `InstallPlan`, a sidecar to a peer-`Deploy` fragment, a resource to a device fragment.
The kernel consumes the generic envelope; the plugin owns the schema, the validation (`OpValidate`), and
the resolution. The build-time `OpEmit` (step/verb fragment), the F6 `grpcSubstrateLifecycle`
(`VenueDescriptor`), and the `HostArbiter`/`HostBuild`/`InvokeProvider`/`RunHostStep` reverse legs are the
existing seams a de-typing rides — no new seam is usually needed, only the consumer stops re-typing.

**Every K-wave move is a generalization, not a mechanical relocation.** Moving a capability's call site
into its owning plugin is R3 ("no duplication; generic, reusable solutions over ad-hoc patches") and
Prioritize Clean Architecture applied to the migration itself (see CLAUDE.md — not restated here). In
practice: reach for an EXISTING generic seam first (`HostBuild`, `InvokeProvider`, `OpResolve`/`OpEmit`,
the `substrateLifecycle` legs) or build ONE generic, F11-reviewed, class-generic action noun — never a
per-word or per-case one; COLLAPSE per-case branches into a single word-keyed data-driven mechanism as
part of the move (per-substrate status collectors + a `switch node.Target` incomplete-seam become ONE
generic `OpStatusCollect`; per-kind `cue_kind` branches become one family); and DELETE every duplicate and
transitional alias the move obsoletes — never re-export it. Rule of thumb: reuse an existing generic seam
or delete the duplicate — rarely invent a new one; most seams the boundary law needs already exist.

**Realized architecture (present state).** The SDK boundary (`github.com/opencharly/sdk`) is extracted;
every verb / kind / step / builder / command, all five deploy substrates (local/pod/vm/k8s/android) with
their pod + vm venue lifecycles, and egress / k8sgen / gpu / arbiter / secrets / enc / tunnel are plugin
candies over the generic seams (`HostBuild("overlay"/"cli"/"step-emit")`, `grpcSubstrateLifecycle`, the
`ExecutorService` reverse legs, the opaque `Substrate`/`DeployVenue.Substrate` payloads). Where a concrete
kind's TYPED shape is still consumed in core — a `spec.<Kind>` field-read, a `kindValueDef`-style per-kind
map, a substrate-word `switch` — that is a known **incomplete seam** being closed one cutover at a time
under this law; the active inventory + sequence live in the cutover plan + each repo's `CHANGELOG/`, never
as a snapshot here.

**Whole subsystems obey the same law.** A generic subsystem is kernel ONLY as one of the four in-core
M-mechanisms (plugin loading / dispatch / the kind-decode materialize / the wire broker); every other
kind-blind mechanism is an sdk kit consumed by plugins. The subsystems still carrying non-trivial core
weight — the build engine, the deploy walk, the OCI `registry.go`+`merge.go` (go-containerregistry), the
status subsystem, the LoadUnified orchestration, every `*_aliases.go` — are v2 migration INVENTORY, each
with a named K-wave exit (K1/K3/K4/K5), never permanent residue: where the boundary test says plugin, it
is an incomplete seam fixed as its own cutover with a named exit, never an indefinite candidate.

## Target architecture (v2) — the direction the boundary law drives toward

The boundary law above is the RULE; this is the END-STATE it converges on (operator-directed,
2026-07-13). CLAUDE.md carries the mandate ("Core is a PLUGIN HOST"); this is its operationalization +
trajectory.

**The architecture, one sentence.** `charly/` core is a plugin HOST and nothing else — it loads plugins,
dispatches to plugins, and brokers the wire; it does not parse config, resolve, build, deploy, or check,
it does not consume the sdk mechanism libraries, and it contains ZERO aliases/shims.

**The three rules (each mechanically enforceable — the P16 triple gate gates all three).**

1. **Everything is a plugin.** Every capability — INCLUDING the project loader, the deploy walk, the
   build engine, and the bed runner — lives in a plugin candy. Core's only jobs: discover/load plugins
   (compiled-in registry + go-plugin gRPC), prescan the CLI grammar from plugin-declared words, dispatch
   words→plugins + fold the kind-decode materialize, and broker the reverse channel (venue executors +
   `InvokeProvider`). → P16 gate (a): the file allowlist (~4k floor).
2. **Core does not import the sdk mechanism layer.** Core imports ONLY the protocol contract — `sdk/spec`
   (wire types) + the proto/go-plugin packages + the Provider/Op vocabulary. `sdk/{kit,deploykit,
   buildkit,loaderkit,vmshared,…}` are for PLUGINS. → P16 gate (b): import-purity (`charly/` has zero
   mechanism-kit imports; the migration-pattern residual import is the tracked "until-K<n>" exception).
3. **Zero aliases/shims.** Every `charly/*_aliases.go` (`type X = deploykit.X`, `var y = kit.Y`) is a
   mid-cutover crutch that keeps a capability CALL SITE in core; the fix is never an alias — it is MOVING
   the call site into its owning plugin. → P16 gate (c): the `charly/*_aliases.go` glob is empty.

**Why the seams die (the radical simplification).** Today's config-resolve / config-persist / oci-inspect
seams exist ONLY because plugins could not load the project or touch the store. Once the loader is
`sdk/loaderkit` (the kind-blind PARSE — already landed, P6/P7) and state is the flock'd,
any-process-safe `sdk/kit` state family (`filelock.go` + `install_ledger.go` + `deployconfig.go` —
already landed, P4/C9; the K4-B decomposition ruled a separate `statekit` package pure churn), a
plugin just LOADS the project itself — same filesystem, same library — and the seam
families COLLAPSE. The reverse channel then shrinks to the two things that genuinely cannot cross a process
boundary: **live venue executors** (re-materialized from `VenueDescriptor`) and **`InvokeProvider`**
(peer-plugin dispatch through the host's registry), plus plugin-binary/cli reentry. Everything else,
plugins do directly via sdk libs.

**Target kernel (~3.5–4.5k LOC — the honest floor).**

| `charly/` keeps | ~LOC |
|---|---|
| `main()` bootstrap + compiled-in plugin registry + plugin cache/loading | ~1k |
| provider registry + in-proc/gRPC transports + prescan (CLI words, kinds) + the kind-decode materialize | ~2k |
| reverse-channel broker (executor re-materialization + `InvokeProvider`) | ~1–1.5k |
| **Total** | **~3.5–4.5k** |

Everything else in today's ~64k → sdk mechanism libraries (loaderkit / enginekit + the existing
kit [incl. its state family] / deploykit / buildkit) consumed by plugin candies (plugin-project [the loader], plugin-build,
plugin-bundle, plugin-check, plugin-box, plugin-status, plugin-oci, the deploy-substrate plugins, the
command plugins).

**The K-wave migration ledger (~64k → ~4k).** Each wave is its own atomic cutover; the in-core residue a
wave leaves is tracked "until-K<n>", never permanent.

| Wave | What | ~LOC out |
|---|---|---:|
| **K1-proper** | the LoadUnified ORCHESTRATION (import queue / discover / namespace / merge) → `sdk/loaderkit`. **Keystone RETIRED** — the kind-blind PARSE (P6, `ParseDoc` → `spec.ParsedProject`, cycle broken via the `loaderkit.Threaded` clause-D DATA snapshot + the swappable `DocParser` seam) + the refs FETCH (P7, `kit.RefsDownloader`) are ALREADY LANDED and compile today; K1-proper is the mechanical relocation of the orchestration. The registry-coupled MATERIALIZE/fold STAYS host (it IS the kind-decode dispatch, v2-consistent). | ~2–2.5k |
| **K2** | engine-client → `sdk/enginekit`; ledger + flock: DELIVERED in `sdk/kit` (filelock / install_ledger / deployconfig, P4/C9) — the residual host state code is loader-coupled (K5 seam-death) or lifecycle-body (K4-A), not a statekit item | ~1k |
| **K3** | the build ENGINE (generate / layers / build / labels / intermediates / localpkg) → `buildkit` + `plugin-build` | ~7.6k |
| **K4** | deploy + config resolution (config_image / deploy / bundle-walk / enc / secrets / network / start / shell / data) → `deploykit` + the deploy/bundle plugins — the CALL SITES move, the aliases die | ~13k |
| **K5** | the seam-death sweep: config-resolve/persist seams deleted; the gathering-arms + retention/feature/settings/hostprobe bodies → plugins; arbiter lifecycle legs → `InvokeProvider`; every remaining `*_aliases.go` deleted; misc verbs dispersed | ~15k |

P16 lands LAST, with all three gates green. GPU host-detection legs are the operator-dropped exception
(revisitable on hardware), not a K-wave item.

## Verification

- `go test ./...` — the registry/transport/schema seams (`TestPluginGRPCRoundTrip`,
  `TestExternalPluginEndToEnd` proves the schema travels over RPC, `TestPluginSchemaSpliceValidation`,
  `TestBuiltinPluginSchemasSplice` is the CI gate that every builtin schema splices).
- `task cue:gen` — regenerates spec + every plugin's params; reproducible (a second run is a no-op).
- `charly box validate` — the candy + `plugin:` block (`validatePluginCandy` checks each capability is
  well-formed and, for `source: builtin`, that the provider is actually compiled in).
- R10: a disposable bed composing a builtin AND an external plugin, driven to a fresh `charly update` — the
  builtin's baked check + the external's out-of-process check both pass.

## Cross-References

- `/charly-internals:go` — the provider registry + the reserved-word spine (verbs/kinds/deploy/steps/builders/commands).
- `/charly-image:layer` — the candy authoring surface the `plugin:` block extends.
- `/charly-check:check` — the plugin-verb check steps (`<word>: <input>` sugar) + ADE (a plugin's own acceptance plan).
- `/charly-build:validate` — `charly box validate` rules.
- `/charly-internals:install-plan` — the `externalDeployTarget` deploy lifecycle (`OpExecute` reverse channel, ledger record) + the `OpEmit` build-time fragment; the deploy wire types in `sdk/spec/deploy_wire.go`.
- `/charly-build:generate` + `/charly-internals:generate-source` — the build-time plugin connect seam + the `emitTasks` placement-agnostic plugin-verb dispatch (`OpEmit` → fragment).

## When to Use This Skill

Invoke before authoring or editing any `plugin:` block, any `sdk/**` code, the plugin SDK, a
compiled-in plugin candy (`compiled_plugins:`) or host-coupled kit candy, an external plugin module, or the
plugin schema/param gen pipeline.
