---
name: go
description: |
  Go CLI development: building the charly binary, running tests, understanding
  the source code structure. Owns the Schema Driven Design (SDD)
  operationalization — the sdk/schema/*.cue → `task cue:gen` generation pipeline
  and the generation-coverage current state.
  MUST be invoked before reading or modifying any Go source file in charly/
  or any sdk/schema/*.cue schema file.
---

# Go - CLI Development

## Overview

The `charly` CLI is a Go program in the `charly/` directory. It uses the Kong CLI framework, go-containerregistry for OCI operations, and YAML parsing for configuration. All computation, validation, and building logic lives in Go. Taskfiles are used only for bootstrapping (building charly itself).

### Unified YAML loader (`LoadUnified`)

The unified format's entry point is `LoadUnified(dir)` at `charly/unified.go`. It reads `<dir>/charly.yml`, recursively resolves the `import:` statement (max depth 8, cycle-safe via visited set), and parses every file as a **YAML multi-document stream** (so bundle files with `---` separators work). Every document is **unified node-form** (name-first): `mergeUnifiedDocs` runs each document through the shared routing core — `classifyDoc` (top-level-key inspection) → the closed `#NodeDoc` CUE gate → `normalizeNodeInto` (the reserved-word-driven node decomposer in `reserved_registry.go`). **`#NodeDoc` (`schema/node.cue`) is the SOLE load-time gate** for every loaded document, the root `charly.yml` and discovered manifests alike. `classifyDoc` does NOT route a legacy kind-keyed / root-shape document — it HARD-REJECTS it with a `charly migrate` hint (the legacy `mergeKindDoc` / `firstKindKey` / `kindKeyedDoc` / `VmDoc` routing was deleted in the `#NodeDoc`-sole-gate cutover). The legacy-shape detector is `rootShapeKeySet` (CUE-derived: `spec.DocDirectives` + every `spec.KindWords` entry, plus the `legacyKindAliases` `deploy`/`check`) — a DETECTOR only, no routing reads it. **F9 BOOTSTRAP PHASE:** before the early `gateSchemaVersion` schema gate, `LoadUnified` runs `runBootstrapPhase(rootData)` (`bootstrap_phase.go`) — it enumerates `providerRegistry.providersInPhase(sdk.PhaseBootstrap)` and invokes each one's `Invoke(OpBootstrap, {config})`, threading the returned (possibly transformed) bytes, so a bootstrap-phase plugin can rewrite the raw root bytes BEFORE validation rejects them. LoadUnified seeds the transformed root into `loadUnifiedInto` via the `fileOverrides` map (keyed on the root's abs path), so the rewrite reaches the actual PARSE + the post-merge gate — not just the early version gate. Bootstrap plugins are compiled-in (in-proc), so this never re-enters the validated-config load. Today only the no-op `candy/plugin-example-bootstrap` registers in this phase — **migrate is NOT a bootstrap-phase transform** (it is the compiled-in `candy/plugin-migrate` `command:migrate` plugin, invoked explicitly by `charly migrate` and by the `refs.go` remote-cache auto-migration Invoke — never as an in-loader byte-rewrite; the load gate keeps the `Run: charly migrate` reject for a stale config, because migration is whole-project file-based + host-coupled and cannot run on root bytes inside `LoadUnified`). Phases are an `sdk.Phase*` set declared per-capability via `ProvidedCapability.phase` (proto field 9, lifted in `buildUnit`/`buildUnitInProc` onto the `phaseCarrier`; `phaseOfProvider` defaults to runtime). A no-op bootstrap plugin (`candy/plugin-example-bootstrap`) returns the bytes unchanged.

`UnifiedFile.ApplyDiscover(rootDir)` walks the **flat generic `discover:` list** after initial merge. `discover:` is `DiscoverConfig` = `[]ScanSpec` (`{path, recursive, manifest}`) — no kind dimension. For each spec, `findEntityDirs` finds directories containing the spec's `manifest` (default `UnifiedFileName` — `charly.yml`, the ONE filename the code knows; a missing discover path is a no-op, not an error), and `applyDiscoveredManifest` validates each discovered document through the SAME `classifyDoc` → `#NodeDoc` gate: a `candy:` node registers a lazy `From:` directory reference (`scanCandy` parses + validates it later), every other node decomposes + merges via `normalizeNodeInto`. Explicit map entries always win over discovered entries. **`ApplyDiscover` runs in the loader's main path (`loadUnifiedInto` depth-0 boundary, for the root AND every namespace), so discovered image nodes (`candy:` nodes carrying `base:`/`from:`, the former `box:`) reach `ProjectConfig` — not just the layer-loading path.** The authoring kind vocabulary is CUE-derived — `spec.KindWords` projected to the `kindWordSet` membership set in `reserved_registry.go`; the former hand `kindKeys`/`kindKeysSet`/`entityKind` lists were deleted.

Projections to today's concrete types: `ProjectConfig()` → `*Config`, `ProjectDistroConfig()` → `*DistroConfig`, etc. Existing `LoadConfig` / `LoadBuildConfigForBox` / `LoadBundleConfig` continue to work unchanged — migration to the unified entry point is incremental.

**Binary-embedded default config (`charly/embed_defaults.go`).** The loader has ONE document-interpretation path (`mergeUnifiedDocs`). The binary-embedded default config is plain node-form YAML at `charly/charly.yml` (`//go:embed charly.yml`, `embed_defaults.go`), parsed by the SAME unified loader as any project `charly.yml` — there is no CUE-source front-end and no compile step: `embeddedDefaults` feeds the embedded bytes straight through the UNCHANGED `mergeUnifiedDocs`, then `applyEmbeddedDefaults` merges the vocabulary in as the lowest-priority base (project-wins). The embedded vocabulary is schema-validated against the sdk schema (`sdk/schema` — `#Distro`/`#Builder`/`#Init`/`#Resource`/`#Sidecar`) through the shared `validateVocabularyCollections` helper (`validate.go`, also used by `charly box validate` for project files) — guarded by `TestEmbeddedDefaults_SchemaConformance`, with `TestEmbeddedDefaults_SameLoaderPath` proving the embed flows through the identical loader core.

### Schema Driven Design (SDD)

The operationalization of CLAUDE.md's "Schema Driven Design (SDD)" pillar — the mandate lives there, the how lives here: the configuration schema comes BEFORE the code, and as much code as possible is GENERATED from the schema. The full pipeline map, source → generator → artifact:

| Source (authored) | Generator | Generated artifact |
|---|---|---|
| `sdk/schema/*.cue` (the base ingress schema) | `task cue:gen` — `cue exp gengotypes` + `sdk/internal/schemagen` (concat/retag/vocab/version), both over the shared `sdk/schemaconcat` | `sdk/spec/cue_types_gen.go`, `spec/vocab_gen.go`, `spec/version_gen.go` |
| each plugin's own `schema/*.cue` | the same pipeline (the superproject `task cue:gen` per-plugin params loop, `-pkg=params`) | `candy/plugin-*/params/cue_types_gen.go` |
| `charly/charly.yml` `compiled_plugins:` | `pluginsgen` (`charly/internal/pluginsgen`, run by `task build:charly`) | `charly/plugins_generated.go` + the repo-root `go.work` |
| `sdk/proto/plugin.proto` | `task proto:gen` (pinned protoc + protoc-gen-go/-go-grpc) | `sdk/proto/plugin.pb.go`, `plugin_grpc.pb.go` |

Validation at every boundary derives from the SAME schema: ingress — `sharedCueSchema` (`charly/cue_schema.go`, the `#NodeDoc` load gate) + `validateKindValueCUE`; plugin inputs — `registerPluginUnitSchema` + `validateAuthoredPluginInput` (`/charly-internals:plugin`); migrations — the declarative table `candy/plugin-migrate/migrations.cue` (`/charly-build:migrate`); egress — the files charly WRITES (`/charly-internals:egress`).

**Reproducibility gates** — regeneration on a clean tree is a NO-OP; drift is an R1 incident: `TestGenReproducible` (`sdk/spec/gen_repro_test.go`), `TestPluginsGenReproducible` (`charly/internal/pluginsgen/main_test.go`), and the documented proto diff gate (the `sdk/Taskfile.yml` `proto:gen` header).

**A high-risk schema shape is spiked first** (RDD — `/charly-internals:strict-policy` "The spike"): prove the def compiles, the generated type round-trips, and the gate accepts/rejects as intended on a throwaway run BEFORE coding against it. The def-level `@go(CharlyName)` breakage documented in the next section was caught exactly that way.

**Generation coverage — the wire-type mandate + the spike-verified exceptions.**
**WIRE TYPES ARE CUE-SOURCED WITHOUT EXCEPTION** (CLAUDE.md SDD): every
`sdk/spec/*_wire.go` host↔plugin / render-context data-carrier struct AND every
plugin's params is a CUE def in `sdk/schema/*.cue` generated by `task cue:gen` —
**hand-writing a wire struct is FORBIDDEN.** A wire type is a plain or DISCRIMINATED
struct, which `cue exp gengotypes` generates faithfully — **RDD-proven live** (a
`{kind!: "a"|"b", a?: …, b?: …}` def generates a real Go struct with the
discriminator + per-variant optional fields), so a wire type NEVER needs a
disjunction. **No `@go(-)` / hand-written type is EVER added without a full RCA +
a live `cue exp gengotypes` spike proving CUE genuinely cannot express it** — an
unverified `@go(-)` is a mandate violation, not an "exception". The ONLY
spike-proven cases are four NON-wire categories (each `@go(-)`'d / documented +
kept in lockstep with its def):

- `sdk/spec/union_types.go` — faithful union/shorthand types for AUTHORED-CONFIG CUE disjunctions (the user's either/or authoring surface, e.g. `VmSource` cloud_image⊻bootc). **RDD spike:** `#X: {cloud_image!: string} | {bootc!: string}` → `type X map[string]any` — `gengotypes` genuinely degrades a disjunction (Go has no sum type). The matching CUE def is `@go(-)`'d. A wire type that would carry a union is a DISCRIMINATED struct instead (a `Kind`/discriminator field + per-variant optional fields — the `deploy_wire` `ReverseOp` tagged-union pattern, RDD-proven to generate) and REFERENCES a disjunction type by name; it never redefines one.
- `sdk/spec/hand_state_types.go` — open-tailed struct+map authoring/state shapes (`PortSpec`, the open-tailed `VmDeployState`). **RDD spike:** `#X: {known?: string, {[string]: _}}` → `type X map[string]any` — the known fields collapse. Mirrored against `@go(-)`'d defs. A new wire type uses an EXPLICIT map field instead of an open tail so it generates.
- `sdk/spec/charly_names.go` — charly-name Go type aliases (def-level `@go(CharlyName)` is broken in cue v0.16.1; see the next section). Not a wire struct.
- `sdk/spec/*_wire.go` (deploy/init/arbiter/gpu/clean/doctor/enc/feature/k8sgen/resource/settings/substrate_template/agent/distro/vm/buildctx) — the host↔plugin & render-context wire structs, **CUE-SOURCED per the mandate** (`sdk/schema/*.cue` → generated). `buildctx.cue` (`InstallContext`/`BuildStageContext`) is the landed reference; any still-hand-written `*_wire.go` is a conversion-in-progress, NOT a sanctioned exception — convert it to a CUE def (a plain/discriminated struct always generates, referencing a disjunction/state type by name where one is genuinely needed).
- `sdk/proto/plugin.proto` — the gRPC TRANSPORT schema, hand-maintained. **RDD verdict (evaluated, not assumed): NOT CUE-migratable.** (a) No `cue→proto` generator exists — `cue exp` offers only `gengotypes` (Go) + `writefs`, `cue export` has no proto output format (cue/json/toml/yaml/text), and `cue get` is proto→CUE (the reverse). (b) CUE has no gRPC-SERVICE concept — the `.proto` defines 4 services with RPC methods, which no CUE codegen models. (c) It carries the `spec` types as `bytes *_json` envelopes (field histogram: 28 string / 8 bool / 5 bytes / prims — ZERO rich-type duplication), so there is nothing to single-source with CUE; the `.proto` IS its own single-source schema (protoc → Go stubs). A spec WIRE STRUCT, by contrast, is always CUE-sourced; the proto is the transport frame around it.
- **`json:"-"` fields (keep-in-Go, drop-from-wire)** — `gengotypes` has NO construct for a field that exists in memory but is excluded from marshaling (it emits a real `json:"<name>,omitempty"` tag instead). **RDD spike (2026-07-12, cue v0.16.x, the P12 check seam):** `kit.CheckResult.DeadlineExceeded bool json:"-"` (an engine-internal retry signal that must never cross the wire) is genuinely inexpressible → a hand-written type carrying a `json:"-"` field is a LEGAL documented exception, with the spike cited at the type.
- `Op.Kind()` (`sdk/spec/charly_methods.go`) — the exactly-one-discriminator cross-field rule, kept in Go because CUE cannot express it as a generable annotation. A method, not a type.

**Spike-proven CAN/CANNOT quick reference (reuse these results — do NOT re-spike settled shapes; DO spike any new shape class):**

| Shape | gengotypes result |
|---|---|
| Plain / DISCRIMINATED struct (`kind!:` + per-variant optionals) | ✅ faithful struct — the wire-type workhorse |
| Reference to another generated def (`Op?: #Op` → `*Op`) | ✅ typed pointer — a def-having embed crosses the wire TYPED |
| `time.Duration` / custom scalar via `@go(,type=…)` override | ✅ (T-P14a `SubstrateKind`, T-P12 `Elapsed` spikes) |
| Untagged-PascalCase-no-omitempty JSON | ✅ via required (`!`) fields + PascalCase CUE names |
| Self-recursive struct (`nested?: [...#Self]`) | ✅ pointer slice `[]*Self` — JSON byte-identical to a value slice |
| `[string]: T` map | ✅ `map[string]T` |
| Disjunction `{a!:…} \| {b!:…}` | ❌ `map[string]any` → hand-written union (authored-config only; a wire type uses a discriminated struct) |
| Open tail `{known?: string, {[string]: _}}` | ❌ known fields collapse → hand_state_types |
| Int-keyed map `[int]: string` | ❌ degrades to an empty struct → re-shape to `map[string]string` or spike-justified `@go(-)` |
| `json:"-"` keep-in-Go field | ❌ no construct → documented hand-written exception |

The member-by-member detail of the `sdk/spec` package is the next section; the step-by-step recipe is "How to change the charly.yml schema (CUE is the single source of truth)" under Common Workflows — neither is restated here.

### CUE is the single source of truth — the `sdk/spec` package

The `charly.yml` ingress schema has ONE author-of-record: the CUE definitions in `sdk/schema/*.cue` — in the sdk contract module (`github.com/opencharly/sdk`, mounted as the `sdk/` git submodule). The Go param structs, the reserved-word vocabulary, and the kind/verb wiring are GENERATED or DERIVED from that source — there are no hand-maintained parallel copies. `charly/go.mod` requires `github.com/opencharly/sdk` with `replace github.com/opencharly/sdk => ../sdk` (in-tree resolution; the require version matters for out-of-tree consumers), and the repo-root `go.work` carries `use ./sdk` (generated by pluginsgen, which guards a missing sdk submodule with a clear `git submodule update --init sdk` error). The pieces:

- **`sdk/spec` — the generated param structs** (import path `github.com/opencharly/sdk/spec`; charly core aliases the types via its scattered alias files — `sdk/vmshared/spec_aliases.go` re-exported through `charly/vmshared_aliases.go`, plus `charly/kit_aliases.go` — unchanged call sites). `task cue:gen` (the sdk repo's task; the superproject `task cue:gen` chains it first, then the per-plugin params loop) regenerates this package from `sdk/schema/*.cue`. Its members:
  - `spec/cue_types_gen.go` — **generated** by `cue exp gengotypes` (then yaml-tag retagged). Carries the `Code generated … DO NOT EDIT` banner; NEVER hand-edit. Every authored param type lives here (`Box`, `Candy`, `Vm`, `Op`, `Deploy`, …).
  - `spec/vocab_gen.go` — **generated** by the companion `sdk/internal/schemagen` (`-mode=vocab`). The CUE-derived reserved-word slices: `KindWords`, `ResourceKinds`, `DocDirectives`, `StepKeywords`, `ContextWords`, `OpFields`, `OpVerbs`, `AuthoringVerbs`.
  - `spec/union_types.go` — **hand-written** faithful union / shorthand types. `cue exp gengotypes` degrades every CUE disjunction to `any`/`map[string]any`/an empty struct, so the matching CUE def is annotated `@go(-)` (suppressing the lossy generated type) and the precise Go type is hand-written here in the SAME package, referenced by the generated structs by name.
  - `spec/charly_names.go` — **hand-written** charly-name aliases (`type BoxConfig = Box`, `type VmSpec = Vm`, …). Def-level `@go(CharlyName)` is BROKEN in cue v0.16.1 (it dangles the fields that reference the renamed def, producing uncompilable Go — RDD-verified on a live spike), so the charly NAME is exposed as a Go type alias here instead of via a def-level attribute. The per-FIELD `@go(GoName,…)` attributes (which DO work) carry the name/pointer/type overrides in `sdk/schema/*.cue`.
  - `spec/gen_repro_test.go` — `TestGenReproducible`, the **reproducibility gate**: re-runs the same `task cue:gen` tools into a temp dir and diffs against the committed `cue_types_gen.go` + `vocab_gen.go`, failing on any drift (skips gracefully when the pinned `cue` CLI is absent).
  - `spec/scalar_aliases.go`, `spec/hand_state_types.go`, `spec/charly_methods.go` — hand-written supporting scalar aliases, runtime state types, and the pure methods (`Op.Kind()`, …) that moved into package `spec` alongside the types they operate on.
- **`sdk/internal/schemagen` (`main.go`) — the companion generator.** Four modes: `-mode=concat` (concatenate `schema/*.cue` into one `schema_spec.cue` compilation unit headed `package spec`), `-mode=vocab` (compile that and emit `spec/vocab_gen.go`), `-mode=version` (emit the `SchemaVersion`/`SchemaFloor` consts → `spec/version_gen.go`), `-mode=retag` (the principled Go yaml-tag transform on the `gengotypes` output → `spec/cue_types_gen.go`). Compiled and documented — never `sed` on generated Go.
- **`sdk/schemaconcat` (`schemaconcat.go`) — the shared PUBLIC concat contract (R3, `github.com/opencharly/sdk/schemaconcat`).** The ONE `ConcatSchema` both the RUNTIME (`charly/cue_schema.go`'s `sharedCueSchema`, over the `sdk/schema` embed FS) and the dev-time generator call to fold every package-less `schema/*.cue` file into one compilation unit, so the schema the runtime validates against and the Go types `gengotypes` produces can never drift. A leaf package depending only on the stdlib `io/fs` abstraction (runtime passes the `sdk/schema` `//go:embed` FS, the generator passes `os.DirFS`).
- **The alias surface (v2 migration INVENTORY — every `charly/*_aliases.go` exits at K3/K4/K5 as its call sites move into plugins; the compile-time parity gate below is a TRANSITIONAL convenience, NOT a permanent design virtue — see CLAUDE.md "Core is a PLUGIN HOST" + the ZERO-ALIASES standing rule).** Every package-main param type is a `type X = spec.X` alias (`BoxConfig`, `Op`, `CandyYAML`, `VmSpec`, `ServiceEntry`, …) — defined in `sdk/vmshared/spec_aliases.go` and re-exported into package main by `charly/vmshared_aliases.go` (kit helpers likewise via `charly/kit_aliases.go`); the hand struct DEFINITIONS were deleted. Because every `BoxConfig{…}` / `[]ServiceEntry` reference throughout package main compiles against the spec types, **the Go compiler IS the field-parity check**: a renamed or removed spec field (or wire-key/type change) fails the build at this surface. Name collisions where the package-main type is a different concept stay hand-written (`CalVer`, `CandyRef`, the runtime `Candy` — the param is aliased as `CandyYAML`).
- **`charly/reserved_registry.go` (package main) — the CUE-derived reserved-word membership sets + the startup VERB bijection gate.** Hosts the membership sets that are the loader's SINGLE reserved-word classification source: `kindWordSet`, `resourceKindSet`, `stepKeywordSet`, `authoredOpFieldSet`, `docDirectiveSet` (each a set view of a `spec.*` slice regenerated by `task cue:gen`; no hand-maintained parallel list). `VerbCatalog` dispatches the generic install verbs; `normalizeNodeInto` (the reserved-word-driven node decomposer) also lives here. The `init()` runs the VERB **bijection** check fail-fast at process start (mirrored as `TestReservedWordRegistry_*`): `checkVerbBijection(VerbCatalog, spec.OpVerbs, spec.AuthoringVerbs)` — a verb can never be added to the schema without a handler, nor a handler kept after its word is dropped. The KIND bijection is `checkKindProviderBijection(spec.KindWords)` in `charly/provider_kind.go` (panics from `registry_bootstrap.go`): it gates ClassKind PROVIDERS against `spec.KindWords`, which is now EMPTY — every authoring kind is plugin-served, so there is no in-core `reservedKindHandlers` map (a kind is decoded by its provider via `runPluginKind`, not a core handler).
- **`charly/uniform_api_gate_test.go` (package main) — the F11 uniform-API gate (`TestNoSinglePluginAPISurface`), the externalization capstone.** Asserts the "generic over ad-hoc" invariant STRUCTURALLY: no provider WORD appears in the plugin↔kernel API SURFACE — not as an `sdk.Op*` selector value, a `sdk.ProvidedCapability`/`StepContract` field name, a reverse-channel RPC method name (`ExecutorService`/`CheckContextService`/`Provider`/`PluginMeta`), or a `hostBuilders` key. The forbidden-word universe is the union of the CUE-derived generic config vocabulary (`spec.OpVerbs ∪ spec.KindWords ∪ spec.OpFields ∪ spec.AuthoringVerbs`) plus every compiled-in non-command provider's `Reserved()` word — which is where the externalized check verbs cdp/vnc/mcp/kube/libvirt/spice/adb/appium enter, since they are plugin-served and NOT `#Op`/`spec.OpFields` fields — minus `genericConceptCollisions` (`venue` — the generic `ExecutorService.Venue` RPC coincides with the `#Op` venue field). The invariant is structural, NOT a user-count (each capability flag has exactly ONE `candy/plugin-example-*` user — "≥1 by construction"). Per-plugin data rides the opaque `Substrate json.RawMessage`; a host MAY call the generic `connectPluginByWord(class, word)` with a specific word ARGUMENT (the word is data, never API shape — those call-sites are not scanned). Sibling of the startup bijection gates; has a teeth arm (a re-introduced provider word must trip it) + fixed RPC-method allowlists (a new reverse RPC is a conscious, reviewed addition).

### import-namespace loader (`UnifiedFile.Import` + `Namespaces`)

`UnifiedFile.Import` (type `ImportList`, YAML tag `import`) is the single composition statement. Its custom `UnmarshalYAML` accepts a mixed-shape sequence: a scalar item → `ImportEntry{Ref: …}` (flat, `Namespace == ""`); a single-key mapping item → `ImportEntry{Namespace: alias, Ref: …}` (namespaced). A matching `MarshalYAML` round-trips both shapes (migrators rely on it). `validateNamespaceAlias` enforces a bare lowercase-hyphenated alias (no dots).

`loadUnifiedInto` processes the queue:

- **Flat entries** are loaded and root-merged into the importing `UnifiedFile` (same root-wins merge that drives same-repo file splits + an imported build-vocabulary override).
- **Namespaced entries** call `loadNamespaceCached(ref, base, nsCache, loadingRepos)`, which loads the target as a fully-resolved, **isolated** `UnifiedFile` (its own flat imports + its own namespaced imports, with a FRESH `visited` set for its file-cycle detection) and mounts it under `merged.Namespaces[alias]`. These entries are NOT flat-merged into the root maps — they are referenced qualified.

`UnifiedFile.Namespaces` (`map[string]*UnifiedFile`, YAML tag `-`, never authored directly) holds the mounted children; `projectConfigCached` projects it to `Config.Namespaces` (`map[string]*Config`, pointer-keyed cache → self-references project safely).

**Cycle-break by REPO IDENTITY (`ns_identity.go`), not pinned version.** Two maps cooperate in `loadNamespaceCached`: `nsCache` is the version-keyed (`canonicalRef`: `repo@version/subpath`) *diamond memo* — it dedups identical refs across a load; `loadingRepos` is the *ancestor/cycle* set, keyed by REPO IDENTITY (`nsRepoIdentity`: a remote ref's `RepoPath`, or a local path's `git remote origin`). BEFORE any fetch, if the ref's repo identity is already in `loadingRepos` (an ancestor still on the load stack), the loader returns that in-progress node — so an import cycle between two projects that import each other (or a transitive back-import of an ancestor still being loaded) terminates even when **the loop's pins diverge**: a back-reference to a DIFFERENT pinned version of an in-progress repo resolves to the in-progress node instead of fetching (and recursing into) a divergent — possibly stale-schema — snapshot. `LoadUnified` seeds `loadingRepos[rootIdentity] = merged` (the root's identity comes from its optional `repo:` field, else `git remote origin`), so any transitive import of the root's OWN repo resolves to the local working tree — **the importing project's namespace pins win**. `loadingRepos` entries are pushed before recursing and popped after (stack-scoped — two SIBLING imports of the same repo at different versions still each load); the root seed is never popped. A whole-repo ref with an empty sub-path resolves to that repo's `charly.yml`. Covered by `TestImportNamespace_DivergentVersionMutualCycle` + `TestNsRepoIdentity` in `ns_identity_test.go`.

### Namespace resolver (`charly/namespace.go`)

The resolver implements Go-package-member semantics over `Config.Namespaces`:

- `splitNamespaceRef(ref)` — splits a qualified ref on its FIRST `.` into `(ns, rest)`; a bare ref returns `ok=false`; the remainder may itself be qualified (`a.b.c` → `"a"`, `"b.c"`).
- `resolveBoxRef(ref)` / `resolveLocalRef(ref)` — bare names resolve in the current `Config`; `ns.name` descends into `c.Namespaces[ns]` recursively, returning the entry plus the `Config` (namespace context) it lives in.
- `resolveNamespacedBases(out, …)` — after the local image set resolves, pulls every namespace-qualified `base:` (and qualified `builder:` ref, but only for images that actually have layers to build) into `out`, keyed by fully-qualified name, iterating to a fixpoint (a pulled-in image may reference a deeper namespaced base).
- `pullNamespacedBox(from, ref, keyPrefix, …)` — descends the namespace chain to the leaf, re-keys the entry's own internal base to the fully-qualified ancestor so the build graph references it correctly, and recurses to pull that ancestor.

The inheritance rule lives here: `distro:`/`build:` are VALUES → inherited across a namespace boundary; `builder:` is a map of namespace-relative REFS → NOT inherited (the consumer declares its own). See the file header comment for the rationale (avoid leaking a base-namespace-relative ref into a consumer where that namespace doesn't exist). `leafName(ref)` strips every namespace prefix to the final member name (`arch.arch-builder` → `arch-builder`); paired with `resolveBoxRef`'s returned namespace `Config` it keys the resolved entity in that `Config.Box` map (used by the reachability walk below).

### Remote-layer resolver (`charly/refs.go` + `charly/layers.go`) — per-entity version + reachability-scoped collection

`@github` layer refs resolve in TWO phases: the `:vTAG` git tag is only the FETCH coordinate (which commit to clone); the layer's own `version:` field — read AFTER fetch — is the authoritative identity that drives dedup + warn-and-newest-wins.

- **`CandyRef` (`charly/refs.go`)** — the single representation of a `require:` / `candy:` ref. It stores the ORIGINAL ref string (`Raw`, with any `@repo` prefix and `:version` suffix); `.Bare()` (the map-key form), `.Version()` (the pinned git tag — the FETCH coordinate, NOT the identity), and `.IsRemote()` are DERIVED. A `resolved` slot carries the qualified sibling key set by `qualifyRemoteSiblingDeps` after a remote layer is fetched, so ONE list serves both the graph (keys on `.Bare()`) and the transitive fetch (keys on the immutable `.Raw`). `Candy.Require` / `Candy.IncludedCandy` are `[]CandyRef` — there are no parallel bare/raw arrays.
- **Two-phase per-entity-version resolution** — `CollectRemoteRefsOpts` (`charly/refs.go`) collects EVERY distinct `(repo, git-tag)` a bare ref is referenced at — it does NOT collapse to one winning tag and does NOT warn (the git tag is just where to clone from). The `ScanAllCandyWithConfigOpts` fix-point (`charly/layers.go`) fetches each `(repo, git-tag)` (tracking scanned `(repo,git-tag,ref)` triples), reads each materialization's per-entity `version:`, accumulates candidates per bare ref, then `pickCandyVersion` arbitrates: **same per-entity version across different git tags → NO warning**, the newest git tag wins for freshness (`compareSemver`); **different per-entity versions → warn once** (naming both per-entity versions + sources) and the newest per-entity version wins (`compareCalVer`). Exactly one materialization per bare ref reaches the layer map, so the graph + intermediates are unchanged. A fetched layer with NO `version:` is a HARD ERROR (no fallback — first-party remotes are backfilled by remote-cache auto-migration, `EnsureRepoDownloaded` → `RunProjectMigrations`). `pickCandyVersion` is the SOLE arbiter for direct AND transitive refs, so a transitive dep can never silently pull a different version of an already-resolved layer. **This is why a repo re-tag of an UNCHANGED layer no longer warns** — the old resolver compared the repo git tag, which advances on every landing.
- **Reachability-scoped collection (`CollectRemoteRefsOpts.collectBox`)** — collection walks ONLY the enabled root images + the namespaced images reachable via their `base:`/`builder:` edges (`resolveBoxRef` + `leafName`), plus local layers' transitive deps. It does NOT scan every image and `kind:local` template of every imported namespace (that over-collection pulled unrelated layers pinned at a different tag — e.g. a namespace's `charly-cachyos` workstation template's `chrome` — and tripped the version policy). Builder edges ARE followed when an image builds (a namespaced `fedora.fedora-builder` is built as an intermediate and needs its `rpmfusion`/`yay` layers); dropping them under-collects ("unknown layer").
- **One unified populator (`populateCandyFromYAML`, `charly/unified.go`)** — both `scanCandy` (discovered-layer-dir path) and `synthesizeInlineCandy` (charly.yml inline path) call it, so they can't drift. The `Has*` predicates (`HasEnv`/`HasPorts`/`HasVolumes`/…) are derived methods; only the filesystem-probe caches (`HasPixiToml`/`HasSrcDir`/…) stay fields.

`charly box reconcile` (see `/charly-build:reconcile`) is the operator tool that aligns the on-disk git-tag pins so every reference of a repo fetches one commit, clearing any residual per-entity-version warning.

### Capabilities — `BoxMetadata` alias + label completeness check

`Capabilities = BoxMetadata` (type alias in `charly/capabilities.go`). `CapabilityLabelMap` lists every field with its OCI label home; `TestCapabilityLabelCompleteness` fails the build if an `BoxMetadata` field lacks a mapping. This invariant keeps `charly bundle from-box` reliable: every field deploy code might consult is readable from a pushed image's labels alone, independent of `charly.yml`.

### Kubernetes substrate (EXTERNAL — `deploy:k8s`, candy/plugin-kube)

`target: k8s` is an EXTERNAL deploy substrate (F1): there is no in-proc k8s DeployTarget — it resolves to `externalDeployTarget` over the reverse channel, served out-of-process by candy/plugin-kube's `deploy:k8s` provider (beside its `kube:` verb). The Kustomize GENERATOR is the COMPILED-IN `candy/plugin-k8sgen` (M13, `verb:k8sgen` serving `OpEmit`; the workload-kind heuristic `selectWorkloadKind` maps the generic `kind:` enum to Deployment/StatefulSet/DaemonSet/Job/CronJob/Pod) — kept SEPARATE from the heavy external plugin-kube because it has no client-go dependency and must resolve in the project-less `from-box` path. `charly/k8s_generate.go` is now a thin in-core SHIM: `GenerateK8sKustomize` lifts the 3 caps scalars (Port/UID/GID) + `spec.Deploy` + `spec.K8s` into a `spec.K8sGenInput`, Invokes the candy (`OpEmit` → `spec.K8sGenReply` manifest docs), validates each doc HOST-SIDE via the M16 egress shim (`ValidateEgressValue`), then writes the `base/`+`overlays/` tree. The host-side `deploy:k8s` preresolver (`charly/k8s_deploy_preresolve.go`) + `charly bundle from-box --target k8s` both call this shim (unchanged signature). The plugin runs `kubectl --context <ctx> apply -k`. See `/charly-internals:install-plan` + `/charly-kubernetes:kubernetes`.

### VM target (external substrate)

`target: vm` is an EXTERNAL deploy substrate, exactly like `local`/`android`/`k8s`: there is no in-proc VM DeployTarget. It resolves to `externalDeployTarget` over the reverse channel, served out-of-process by `candy/plugin-deploy-vm`'s `deploy:vm` provider. UNLIKE k8s, the vm substrate DOES consume the InstallPlan IR — the plugin walks the plan via the SAME shared `sdk/kit.WalkPlans` the local deploy uses, but the executor the reverse channel serves is the **guest `SSHExecutor`** (`sdk/kit/deploy_executor_ssh.go`), so the same walk runs INSIDE the guest (bash bodies via `ssh guest 'sudo bash -s'`). The `DeployExecutor` interface (`sdk/kit/deploy_executor.go`) decouples "how shell commands run" from the walk — `ShellExecutor` + `SSHExecutor` are the two implementations.

The VM venue lifecycle (boot the domain, build the guest SSH executor, nested pod-in-guest, teardown, the `charly vm` Start/Stop/Status/Logs/Shell/Rebuild) is IMPLEMENTED IN THE PLUGIN `candy/plugin-deploy-vm/lifecycle.go` (`Lifecycle:true`) over generic seams — `sdk/kit` (ssh-config stanza, guest waits, charly delivery), `HostBuild("cli")` (the `charly vm`/`charly box build` family), and the served guest executor reverse channel (nested pod-in-guest). Core keeps ONLY generic seams + host-resolved DATA: the vm `lifecyclePrepareHook` + `lifecyclePostTeardownHook` (`charly/vm_lifecycle_preresolve.go`) ship `spec.LifecyclePrepareInput` (the k8s/android-preresolver-shaped DATA seam), and the generic `grpcSubstrateLifecycle` proxy (`charly/substrate_lifecycle_grpc.go`) — the `substrateLifecycle` interface (`charly/deploy_substrate_lifecycle.go`) — consults them by word and persists the returned `VmDeployState`. Both pod and vm own a real venue lifecycle, each externalized to its plugin.

`charly bundle add vm:<name>` dispatches through `bundle_add_cmd.go::dispatchNode` → `ResolveTarget` → `externalDeployTarget` (no per-kind dispatch function); `bundle_add_cmd_vm.go` carries the host-side VM-only helpers that REMAIN (`vmNameFromDeployName`, `sshReverseRunner`, `resolveVmSshUser` / `resolveVmSshPort`, `saveVmDeployState`, `removeVmDeployEntry`). Full architecture + preflight flow lives in `/charly-internals:vm-deploy-target`.

### YAML surface ↔ Go identifier convention

The codebase keeps wire format (YAML keys) and internal names (Go fields/types) in strict symmetry — plural YAML keys get plural Go identifiers, singular get singular. The singular `builder:` / `distro:` / `init:` top-level keys in the embedded build vocabulary (`charly/charly.yml`) and project `charly.yml` carry singular Go identifiers: `BuilderMap`, `BoxConfig.Builder`, `BuilderConfig.Builder`, `DistroConfig.Distro`, `InitConfig.Init`. The rule: if you change a YAML tag, also rename the Go identifier. Tests enforce this indirectly — struct literals won't compile if they disagree. Note: the OCI **label key** is grouped under `platform.*` / `builder.*` sub-namespaces — see `LabelPlatformDistro`, `LabelPlatformFormat`, `LabelBuilderUse`, `LabelBuilderProvide` in `labels.go`. Label wire-names are decoupled from YAML/Go identifiers by design.

### Kong `default:"withargs"` for parent+leaf commands

Kong normally treats a struct as either a branch (has child `cmd:""` subcommands) OR a leaf (accepts `arg:""` positionals and has a `Run()` method) — not both. When you want both shapes on the same parent command (e.g., `charly config <image>` runs setup AND `charly config mount|status|…` dispatch to subcommands), tag the default child with `default:"withargs"`. Kong then dispatches to that child when the first token doesn't match a subcommand name, passing positional args/flags through.

One use in the codebase:
- `charly/config_image.go` — `BoxConfigCmd.Setup` is the default (`default:"withargs"`); `charly config <image>` routes through `BoxConfigSetupCmd` while `charly config mount|status|…` dispatch explicitly.

`charly check` — now the compiled-in `command:check` plugin (`candy/plugin-check`) — needs no such pattern: every live-container verb (`wl`/`cdp`/`vnc`/`dbus`/… and `libvirt`) is an out-of-process declarative verb, NOT a `charly check` subcommand, so no subcommand name can shadow the `charly check live <image>` positional.

### Mode purity: `LoadConfig` must NOT read `charly.yml`

OCI labels are written exclusively from `charly.yml` at `charly box build` / `charly box generate` time. `charly.yml` is deploy-mode state and must never bleed into the baked image. The key guarantee lives in `charly/config.go:LoadConfig` — it calls `LoadConfigRaw` only, with no `MergeDeployOverlay`.

**The rule**: every build-mode command (anything under `charly box …`) calls `LoadConfig`. If you ever re-introduce `MergeDeployOverlay` inside `LoadConfig`, you will silently contaminate OCI labels with whatever is in the user's local `charly.yml` — exactly the bug that made images bake `ports: ["5900:5900","9250:9222"]` from a stale `charly.yml` entry instead of the `charly.yml`-declared `["5900:5900","9222:9222","9224:9224"]`.

Deploy-mode commands (`charly config`, `charly start`, `charly stop`, `charly update`, `charly bundle add`, `charly bundle del`, `charly shell`, `charly cmd`, `charly service`, `charly vm create`, …) read labels via `ExtractMetadata` and then apply the deploy overlay explicitly via `MergeDeployOntoMetadata(meta, dc, instance)`. This split is load-bearing — never collapse it.

**Host-deploy specifics**: `charly bundle add host` is deploy mode (reads both charly.yml and charly.yml), not build mode — despite looking like "install on host, not into an image". The compiler (`BuildDeployPlan` in `install_build.go`) is pure and shared with build mode, but the invocation path reads charly.yml for `add_candy:` and `install_opts:` like every other deploy-mode command.

### InstallPlan IR — the shared intermediate representation

The DEPLOY paths (pod/vm + external [local/k8s/android]) route through a shared IR; build-mode Containerfile emission is a SEPARATE generator (`WriteCandySteps` → `EmitTasks` in `sdk/deploykit`, relocated from `charly/generate.go` in #67, driven by `candy/plugin-build` over the envelope + `HostBuild("render-seam")`; `emitTasks` in `charly/tasks.go` is a thin shim to `deploykit.Generator.EmitTasks` that stays for the pod-overlay), NOT the IR. The k8s substrate is EXTERNAL and does NOT consume the IR — it generates a Kustomize tree host-side (see "Kubernetes substrate" above). Flow:

```
Layer + ResolvedBox + HostContext
    → BuildDeployPlan (install_build.go) [pure; deploy-path only, NOT charly box build]
    → InstallPlan (install_plan.go)
    → DeployTarget.Emit (OCITarget/PodDeployTarget) / UnifiedDeployTarget lifecycle
       ├── OCITarget (build_target_oci.go)          → Containerfile text (pod-overlay add_candy: synthesis)
       ├── PodDeployTarget (deploy_target_pod.go)   → overlay + quadlet
       └── externalDeployTarget (deploy_target_external.go) → out-of-process plugin over the OpExecute reverse channel
                                                              (deploy:local — candy/plugin-deploy-local walks the IR
                                                              via kit.WalkPlans, host-engine steps via RunHostStep;
                                                              deploy:vm — candy/plugin-deploy-vm runs the SAME walk
                                                              INSIDE the guest over the guest SSHExecutor, with the
                                                              vm venue lifecycle plugin-implemented over the proxy;
                                                              deploy:k8s — host preresolver generates the Kustomize
                                                              tree, plugin runs kubectl apply -k; deploy:android)
```

`OCITarget` is constructed only by `PodDeployTarget`; `charly box build`/`generate` emit via the `WriteCandySteps` → `EmitTasks` generator in `sdk/deploykit` (`deploykit.Generator`, relocated from `charly/generate.go` in #67; `emitTasks` in `charly/tasks.go` is a thin shim to `deploykit.Generator.EmitTasks` that stays for the pod-overlay), sharing the package-cascade / shell-snippet / localpkg compiler helpers with the IR. Full reference lives in **`/charly-internals:install-plan`** — go there before touching any of those files. Supporting Go files (ledger, builder_run, shell_profile, reverse_ops, service_render, deploy_ref, hostdistro, migrate_services_tool) are covered in **`/charly-internals:local-infra`**.

### VM-path architecture

The VM path spans the following module topology:

| File | Role |
|---|---|
| `sdk/spec/cue_types_gen.go` (generated) | `VmSpec` (= `Vm`) + `VmSource` discriminated union (cloud_image / bootc) + `VmChecksum` + `VmNetwork` + `VmSSH` + `VmKeyInjection` |
| `sdk/spec/cue_types_gen.go` (generated) | `VmCloudInit` + `VmCloudInitUser/File/Network/Mirrors` + `VmCharlyInstall` (auto/scp/url/skip state machine) |
| `sdk/vmshared/libvirt_yaml.go` | `LibvirtDomain` + 30+ sub-types (features, CPU, clock, memory backing, numatune, cputune, devices, seclabel, launch security, resource, sysinfo) — the opencharly YAML-facing shape of the `libvirt:` stanza |
| `candy/plugin-vm/libvirt_yaml_bridge.go` | `RenderDomainXML`/`BuildLibvirtDomainXML` pure functions (build a `libvirtxml.Domain` tree, marshal to XML) + `buildDomainDevices` device emission (passt backend, portForward attribute order, virtio-gpu default, SMBIOS credentials, `XMLPassthrough` merge) |
| `sdk/vmshared/qemu_render.go` | `RenderQemuArgv` for direct-QEMU backend |
| `sdk/vmshared/cloud_init_render.go` + `cloud_init_iso.go` | `RenderCloudInit` + `ResolveKeyInjectionChannels` + `composeUsers` (adopt-merge) + `WriteSeedISO` via xorriso/genisoimage/mkisofs |
| `charly/vm_cloud_image.go` + `sdk/kit/http_fetch.go` | `BuildCloudImage` pipeline: fetch URL (`FetchQcow2`, in sdk/kit) + sha256 sidecar + resize + seed ISO render |
| `sdk/kit/charly_install.go` | `kit.EnsureCharlyInVenue` — the GENERIC "copy charly into a running venue" mechanism (container `podman cp` / VM-SSH `scp` / host `install`, all via `DeployExecutor.PutFile`): returns the `charly` invocation command, copying the host `os.Executable()` to a non-`$PATH` `/tmp/charly-<calver>` on absence/older (idempotent, never shadows a packaged charly). Used by nested from-image delegation, so an image need not bake the `charly` layer. `kit.EnsureCharlyInGuest` is the VM-deploy strategy wrapper (auto/scp/url/skip) layered on top |
| `sdk/vmshared/ovmf_paths.go` | `ResolveOvmfPaths` (per-distro OVMF_CODE/VARS paths) + `EnsurePerVmNvram` + `ResolveOvmfForSpec` (bios-sentinel returning empty strings) |
| `sdk/schema/vm.cue` + `cue_kind_vm.go` | `#Vm` — the closed CUE schema validating VmSpec + the `#LibvirtDomain`/`#VmCloudInit` subtrees (the Go VM/libvirt validators were deleted; CUE owns it via the per-kind registry) |
| `sdk/kit/deploy_executor*.go` | `DeployExecutor` interface + `ShellExecutor` + `SSHExecutor` with `WaitForSSH` + `WaitForCloudInit` |
| `charly/deploy_target_external.go` | `externalDeployTarget` — the adapter the external `vm` substrate (and local/android/k8s) routes through |
| `charly/deploy_substrate_lifecycle.go` + `charly/substrate_lifecycle_grpc.go` + `charly/vm_lifecycle_preresolve.go` | the generic `substrateLifecycle` interface + the `grpcSubstrateLifecycle` proxy + the vm `lifecyclePrepareHook` / `lifecyclePostTeardownHook` (the host-resolved DATA + residual ephemeral cleanup); the vm venue lifecycle itself lives in `candy/plugin-deploy-vm/lifecycle.go` |
| `candy/plugin-deploy-vm/` | the out-of-process `deploy:vm` plugin — the plan WALK (`kit.WalkPlans` over the guest `SSHExecutor`) + the venue lifecycle (`lifecycle.go`, over `kit` + `HostBuild("cli")` + the served guest executor) |
| `charly/bundle_add_cmd_vm.go` | host-side VM-only deploy helpers that REMAIN (`vmNameFromDeployName`, `sshReverseRunner`, `resolveVmSshUser` / `resolveVmSshPort`, `saveVmDeployState`, `removeVmDeployEntry`); `charly bundle add vm:<name>` itself dispatches through `dispatchNode` → `ResolveTarget` → `externalDeployTarget` |
| `candy/plugin-vm/vm_create_spec.go` + `charly/vm_build.go` | `charly vm create` CLI wiring (in the `command:vm` plugin) + the VM-disk build ENGINE (in core TODAY — K3 build-engine migration inventory, not permanent core; reached via `HostBuild("vm-build")`) reading `kind: vm` entities |
| `sdk/vmshared/libvirt_helpers.go` + `libvirt_yaml_listen.go` | helpers shared by the libvirt YAML bridge + `qemu_render` argv emitter (`VmRuntimeParams`); structured `<listen>` support for `LibvirtGraphics` |

**`unified.go` VM support** (C2-substrate): `"vm"` is NO LONGER a `spec.KindWords` kind — the 5 substrate kinds (pod/vm/k8s/local/android) were externalized to the compiled-in **candy/plugin-substrate** (`kind:pod/vm/k8s/local/android`, `Structural:true`), so `vm` LEFT `spec.KindWords` + the `#Node` disjunction (no `#VmArm`) but STAYS in `spec.ResourceKinds` (member nesting) and its `#VmValue` def is KEPT for the host-side value gate. A `vm:` node resolves via `recognizedKind` (the compiled-in provider) → `runPluginKind` → `foldSubstrateKind`, which host-decodes the CANONICAL node via the core loader (`buildBundleNode` for a deploy shape → `uf.Bundle`, `decodeNodeValue` for a bare template → `uf.VM` `map[string]*VmSpec` — the C2-substrate TEMPLATE fold arm), validates its value against the KEPT `#VmValue` def (`validateKindValueCUE`), threads it to plugin-substrate's `OpLoad` via `op.Env` (`spec.StructuralKindLoadEnv.Standalone`), and folds the plugin's ECHO into the typed map. `VmSpec = spec.Vm` is the generated param alias. `#NodeDoc` is the sole STRUCTURE gate; a residual legacy `vm:`-keyed (or `vms:`-plural) document is hard-rejected by `classifyDoc` with a `charly migrate` hint (`rootShapeKeySet` unions `spec.ResourceKinds` so the substrate words stay legacy-detectable).

Full subsystem references: `/charly-internals:vm-spec`, `/charly-internals:libvirt-renderer`, `/charly-internals:cloud-init-renderer`, `/charly-internals:vm-deploy-target`, `/charly-internals:ovmf`, `/charly-internals:cutover-policy`.

### Self-exec coordination: host → container AND host → host

The `charly` binary self-execs in two distinct directions.

**Host → container** — the host `charly` delegates to a container-baked (or copied-in) `charly` via `exec … charly <subcommand>`. The surviving site is **nested from-image delegation**: a from-image plan re-invokes `charly` inside the venue, and `kit.EnsureCharlyInVenue` (`sdk/kit/charly_install.go`) copies the host binary in on demand when the venue lacks it. The best-effort desktop notification in `charly/notify.go` (`sendVenueNotification`) is NOT a self-exec site — it drives the venue's session bus with `gdbus` directly, no in-container `charly`.

**Host → host (none)** — there is NO host→host self-exec for check verbs. Every live-container verb (`wl`/`cdp`/`vnc`/`dbus`/`mcp`/`record`/`kube`/`adb`/`appium`/`spice`/`libvirt`) dispatches OUT-OF-PROCESS through the provider registry to its plugin candy (EXEC-based verbs drive the venue over the `DeployExecutor` reverse channel; endpoint verbs dial a host-pre-resolved address) — never by spawning a `charly` subprocess. charly's core carries no in-proc live-verb dispatch machinery.

**The rule:** whenever you rename a subcommand path crossed by the surviving host→container self-exec site (nested from-image delegation), edit the host-side invocation strings AND plan a coordinated rebuild of every image that bakes the `charly` layer (affected images: grep `charly.yml` for `- charly$`).

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Build | `task build:charly` | Compile to `bin/charly` and install as Arch package. **Rewrites the TRACKED `pkg/arch/PKGBUILD` `pkgver=` stamp**, so it leaves the `pkg/arch` submodule dirty (` M PKGBUILD`) and, via the gitlink, the superproject too. Expected, not a stray artifact — `git -C pkg/arch checkout -- PKGBUILD` before staging a commit, or the pointer bump rides along uninvited |
| Install | `task build:install` | Install charly as Arch package (uses pre-built binary) |
| Run tests | `cd charly && go test ./...` | Run all tests |
| Run specific test | `cd charly && go test -run TestName ./...` | Run single test |
| Vet | `cd charly && go vet ./...` | Static analysis |
| Format | `cd charly && gofmt -w .` | Format code |

## Project Directory Structure

```
project/
├── bin/charly                     # Built by `task build:charly` (gitignored)
├── charly/                        # Go module (kong CLI, go-containerregistry)
│   └── charly.yml             # The binary's embedded default config (//go:embed,
│                              # embed_defaults.go): distro/builder/init/resource
│                              # build vocabulary + the sidecar: template library.
│                              # Parsed by the SAME unified loader as any project
│                              # charly.yml; a project ships none of it.
├── sdk/                       # Git submodule (github.com/opencharly/sdk) — the plugin
│                              # contract module: root package sdk, sdk/kit, sdk/spec,
│                              # sdk/proto, sdk/schema/*.cue, sdk/schemaconcat, sdk/vmshared;
│                              # its own Taskfile owns `task cue:gen` + `task proto:gen`
├── .build/                    # Generated Containerfiles (gitignored)
├── charly.yml                  # Image definitions
├── Taskfile.yml               # Bootstrap tasks only
├── taskfiles/                 # Build.yml, Cue.yml, Setup.yml
├── candy/<name>/             # Layer directories (160 layers)
├── plugins/                   # Git submodule (opencharly/plugins)
└── templates/                 # supervisord.header.conf (referenced by init.supervisord.header_file)
```

Submodule convention: `plugins/` is a submodule rooted at the
`opencharly/plugins` repo, and `sdk/` is a submodule rooted at the
`github.com/opencharly/sdk` repo. Clone with `--recurse-submodules` or run
`git submodule update --init` after a plain clone. See
`/charly-internals:skills` for the skill-authoring and sync conventions.

## Source Code Map

### Core Generation

| File | Purpose |
|------|---------|
| `main.go` | CLI entry point (Kong framework). `CLI` struct carries two global path fields: `Dir` (`-C` / `--dir` / env `CHARLY_PROJECT_DIR`) and `Repo` (`--repo` / env `CHARLY_PROJECT_REPO`). When `Repo` is set, `main()` resolves it via `ResolveProjectRepo` and assigns the cache path back into `Dir`; when `Dir` is non-empty (after that resolution), `main()` calls `os.Chdir(Dir)` **before** `ctx.Run()` — one-line intervention that propagates to every `os.Getwd()` call site throughout build-mode commands without requiring per-command plumbing. `--repo` and `--dir` are mutually exclusive (fast-fail). Covered by `TestCharlyDir_FlagChdir`, `TestCharlyDir_Errors`, `TestCharlyRepo_FlagChdir`, `TestCharlyRepo_DirConflict`, `TestCharlyRepo_DefaultExpansion` in `main_dir_test.go` + `main_repo_test.go`. Load-bearing for `charly mcp serve` inside a container where cwd resolves to `/workspace` (the `charly-mcp` layer default) — either bind-mounted with the project, or empty in which case the externalized MCP server's managed `--repo default` child prefix falls back to the upstream repo (`computeProjectPrefix` in `candy/plugin-mcp/serve.go`). |
| `main_repo.go` | `--repo` resolver. `DefaultProjectRepo = "github.com/opencharly/charly"`. `normalizeRepoSpec(spec)` handles four spec shapes: `"default"` literal, bare `owner/repo` (auto-prefix `github.com/` when first segment has no dot), bare `owner/repo@ref`, host-qualified `host.tld/owner/repo[@ref]`. `ResolveProjectRepo(spec)` reuses `EnsureRepoDownloaded` from `refs.go` so the project-repo cache shares `~/.cache/charly/repos/` (override `CHARLY_REPO_CACHE`) with the existing remote-layer cache. Empty version triggers `GitDefaultBranch` resolution. |
| `config.go` | `charly.yml` parsing, inheritance resolution. `BuildFormats` type. `Distro` field. `ResolvedBox.Tags` (union). `SupportsTag()`, `SupportsBuild()` methods |
| `format_config.go` | `DistroConfig` (with per-distro `Formats`), `BuilderConfig` types. `BuildFile` loader struct matches the three top-level build-vocabulary sections (`distro:`, `builder:`, `init:`). `LoadBuildConfigForBox` reads the project `charly.yml` (via `LoadUnified`, with the embedded build vocabulary merged in as the project-wins base) and splits it into `DistroConfig` / `BuilderConfig` / `InitConfig` views. Per-image config resolution with remote ref support |
| `format_template.go` | Go `text/template` rendering engine. Template helpers: `cacheMounts`, `cacheMountsOwned`, `quote`, `default`, `splitFirst`, `replace`, `join`. `InstallContext`, `BuildStageContext` types |
| `layers.go` | Layer scanning, file detection. `CandyYAML` (the `= spec.Candy` generated param alias — no hand struct; see `spec_aliases.go`), CUE-decoded via `cue_loader.go`; load-time top-level typo-detection via the `rejectUnknownCandyTopLevelKeys` guard — no custom `UnmarshalYAML`. `Task` struct + `Kind()` method (exactly-one-verb). `derivePackageSectionsFromCalamares` is the SOLE package-surface populator: every `distro:` key (bare / versioned / compound) → a per-distro `tagSections` entry (NOT a shared format section — that collapse caused the non-deterministic deb-repo bug); top-level `package:` → `topPackages` (folded at resolve time); arch `aur:` keeps its `aur` format section. `compileSystemPackageSteps` (`install_build.go`) cascades these — see `/charly-internals:install-plan`. The runtime `Candy.ExternalBuilder` field (the reserved word of an EXTERNAL builder plugin a candy selects; from the candy manifest `external_builder:`) lives here, populated by `populateCandyFromYAML` (`unified.go`) and resolved at build via `OpResolve` (`sdk/deploykit EmitExternalBuilderStages`, relocated in #67). |
| `tasks.go` | **All task emission logic** — per-verb emitters (`emitMkdirBatch`, `emitCopy`, `emitWrite`, `emitLinkBatch`, `emitDownload`, `emitSetcapBatch`, `emitCmd`, `emitBuild`), `emitTasks` orchestrator, `stageInlineContent` (content-addressed), `resolveUserSpec`, `taskSubstPath`, `taskUnresolvedRefs`. Adjacent-coalescing (`taskCoalescesWith`). **Shell-quoting helpers:** `shellSingleQuote(s)` for standard `'...'` escaping (used by LABEL values + `emitDownload` env entries) and `shellAnsiQuote(s)` for bash ANSI-C `$'...'` quoting (used by `emitCmd` so multi-line script bodies survive podman's line-oriented Dockerfile parser). **`emitDownload` env rule:** uses `export VAR=val;` (semicolon-terminated) not `VAR=val cmd`, because bash expands `${VAR}` in URL arguments before the cmd-prefix environment is assembled. ~430 lines, single home for install-task codegen. **`plugin:` verb case + `emitPluginFragment`:** a `run:` plugin step emits placement-agnostically — a builtin `ProvisionActor` renders an act shell RUN in-proc, any other resolved provider renders via `emitPluginFragment` → `Invoke(OpEmit)` → `spec.EmitReply.Fragment` spliced verbatim (in-proc for a builtin, go-plugin gRPC for an external). See `/charly-internals:plugin` + `/charly-build:generate`. |
| `generate.go` | The build-mode Containerfile render DRIVE (`Generate` / `generateContainerfile` / `WriteCandySteps` / `WriteLabels` / `writeJSONLabel` / `WriteBootstrap` / `EmitBuilderStages` / `EmitBuilderArtifacts` / `EmitExternalBuilderStages` / `EmitExternalBuilderArtifacts` / `GenerateTraefikRoutes` / `EmitTraefikRouteStage` / `EmitInitFragmentStages` / `EmitInitAssembly`) moved to `sdk/deploykit` (`deploykit.Generator`) in #67, driven by `candy/plugin-build` over the resolved-project envelope + `HostBuild("render-seam")`; the `charly/generate.go` top-level `Generate`/`writeCandySteps` orchestrator is DELETED. What STAYS in `generate.go`: `NewGenerator` (connects the project's external plugin candies via `loadProjectPlugins` — the build-time plugin connect seam); the builder `OpResolve` resolve helpers `resolveBuilderStage` / `resolveExternalBuilder` (reached via `HostBuild("render-seam")` + the pod-overlay); `emitBakedPlugins` (used by `toDeploykit` + `HostBuild("bake-plugins")`); `generateInitFragments` (a shim to `toDeploykit().GenerateInitFragments`, for the pod-overlay); `writeContextIgnore`; the status helpers (`resolveStatus`/`candyStatus`/`worstStatus`); the host-fs helpers (`createRemoteCandyCopies`/`materializeBuildConfigAsset`/`rewriteHeaderCopyForRemote`/`candyByName`/`candyCopySource`); `buildStageContext`/`collectBuilderRuntimeEnv`/`globalOrderForBox`/`resolveUserContext`. The builder stage emission is `deploykit.Generator.EmitBuilderStages` / `EmitBuilderArtifacts` / `EmitExternalBuilderStages` / `EmitExternalBuilderArtifacts` (relocated in #67); the builder `OpResolve` resolve helpers (`resolveBuilderStage` / `resolveExternalBuilder` in `generate.go`) STAY. `WriteCandySteps` (deploykit) orchestrates per-layer: packages → `EmitTasks` (deploykit; `emitTasks` in `charly/tasks.go` is a thin shim to `deploykit.Generator.EmitTasks` that stays for the pod-overlay) → builders → USER reset. **Package resolution goes through the SAME `resolveCascadePackages` (`install_build.go`) the deploy compiler uses** — ONE distro-specificity cascade for build AND deploy (folds the top-level `package:` base + unions distro tag sections most-specific-first), then renders the primary format's install template; non-primary build formats (`aur`) emit from their own format section. Config-driven format install and bootstrap from the build vocabulary (`distro:` + `builder:` sections — the embedded default lives in `charly/charly.yml`); builder STAGE templates moved out to the plugins' `kit.BuilderResolve` (C10 — the `builder:` section retains detection + cache mounts + the deploy host phase + pixi's context inputs). **`WriteLabels` (deploykit) is called at the END of the final stage (after the final `USER` directive)** — the volatile `LabelDescription` value would otherwise invalidate every downstream RUN/COPY on a baked-plan edit; with LABELs-at-end, only the LABEL steps themselves re-emit (cache preserves all install work). `writeJSONLabel` (deploykit) routes every JSON label value through `shellSingleQuote` so embedded `'` chars in test commands (`awk '{print $1}'`) don't break podman's `key=value` LABEL parser. |
| `validate.go` | The host-natural validation checks that need the raw loader — the ONLY validation left in core: CUE-conformance (`validateCandyCUESchemas` / `validateProjectCUESchemas`), `validateVocabularyCollections`, `validateBuildAndDistro`, `validateBuildTunables`, `validateMergeConfig`, `validateBuilderRefs`, `validateBoxBaseFrom`, `validateRemoteCandies`, `boxEntityWireYAML`, `isNodeFormFile`. Format/builder validation against config definitions (not hardcoded maps). The per-kind/op/candy/graph rule ENGINE (`validateCandyTasks` / `validateCandyContents` / `validateAliases` / `validateVolume` / `validateCandyReferences` / the box+candy DAGs / `validateOps`) moved to the compiled-in `command:box` plugin (`candy/plugin-box/{validate.go, validate_rules.go, validate_graph.go, validate_check.go}`), reading the resolved-project envelope. |
| `version.go` | CalVer computation |
| `scaffold.go` | `new layer` scaffolding (single-layer dir creation with stub `charly.yml`) |
| `box_fetch_reentry.go` | The hidden `charly __box-fetch` / `__box-refresh` core reentry points behind the COMPILED-IN candy/plugin-authoring command:fetch / command:refresh verbs (P14b). The repo resolver (`ResolveProjectRepo` → `EnsureRepoDownloaded`: `CHARLY_REPO_OVERRIDE` + the refs-backend dispatch + the command:migrate auto-migration) is host-coupled, so the authoring plugin re-runs these hidden commands over `HostBuild("cli")` (the SAME seam candy/plugin-box's `pkg` verb uses for `__box-pkg`). The `box set/add-candy/rm-candy/write/cat` authoring verbs + the `AddCandyToBox`/`RemoveCandyFromBox` yaml.Node helpers + `resolveProjectFile` (the path-traversal guard for `box write` / `box cat`) MOVED to the compiled-in `command:authoring` plugin (`candy/plugin-authoring`, P14b) — they run PURE on sdk/kit (`kit.SetByDotPath` / `kit.MappingChild` / `kit.SaveYAMLNodeFile`) + stdlib, zero core reentry. The create-side `box new project/box/candy` ENGINE is `kit.ScaffoldProject` / `kit.AddBox` / `kit.ScaffoldCandy` (shared with candy/plugin-box's command:new). Tested in `scaffold_project_test.go` (the kit-scaffolder tests) + `candy/plugin-authoring/authoring_edit_test.go` (the moved helpers). |
| `sdk/kit/yaml.go` *(SDK kit, not `charly/`)* | `kit.SetByDotPath(path, dotpath, valueYAML)` + `kit.MappingChild(m, key)` — the generic comment-preserving YAML node utilities used by `charly box set` and the `command:candy` plugin. Walk `*yaml.Node` trees; create intermediate mappings on demand; reject descent into scalars. Tested in `sdk/kit/yaml_test.go` (`TestSetByDotPath_ScalarReplacement` + list-value, intermediate-mapping, scalar-descent-error cases). |

### Plugins, external deploy & build-time emit

Provider/registry/SDK internals are owned by **`/charly-internals:plugin`**; the external-deploy lifecycle + wire types by **`/charly-internals:install-plan`**. The file map:

| File | Purpose |
|------|---------|
| `deploy_target_external.go` | `externalDeployTarget` — Add/Test/Update/Del for an OUT-OF-PROCESS deploy provider over the executor reverse channel (`OpExecute`); records teardown ops to the ledger keyed on `computeDeployID` |
| `plugin_step_external.go` | `externalPluginStepProvider` — the `StepProvider` for `StepKindExternalPlugin` (a `run: plugin: <verb>` step served by an OUT-OF-PROCESS plugin). `EmitOCI`→`Invoke(OpEmit)` fragment (reusing `emitPluginFragment`, R3) is the only in-proc Emit. At DEPLOY time the step is executed via `executeExternalPluginStep`→`InvokeWithExecutor(OpExecute)` on the executor reverse channel — reached as a host-engine step over `RunHostStep` during the external local/vm deploy walk — recording the reply's dynamic `ReverseOp`s to the `CandyRecord`. The `executorInvoker` interface (`InvokeWithExecutor`, satisfied SOLELY by `*grpcProvider`) is the discriminator. The IR kind `StepKindExternalPlugin` + `ExternalPluginStep` struct live in `install_plan.go`; `compileActOp` (`install_build.go`) routes an external (`executorInvoker`) plugin verb to it; `allStepKinds` + the bijection gate (`provider_step.go`) register it. Owned by `/charly-internals:install-plan`. |
| `plugin_prescan.go` | Byte-gated, additive parse pre-scan: `prescanPluginManifest` registers an external deploy SUBSTRATE word (`ClassDeployTarget`, consumed by `unified.go`'s loader path before the provider connects), an external COMMAND word (`ClassCommand`, registered via `registerDeclaredExternalCommand`, snapshot via `declaredExternalCommandWords`, consumed by `prescanProjectCommandWords` in `main.go` before `kong.Parse`), AND (F4) an external KIND word (`ClassKind` → `registerDeclaredKind`; `recognizedKind` = connected-OR-prescanned). **F4 kind connect:** unlike a deploy substrate (which defers to the bundle builder) or a command (lazy-connect on invocation), a `kind: <plugin-word>` entity must DECODE its body during load (`runPluginKind`), so `connectDeclaredKindPlugins` (called at the depth-0 loader hook right after the prescan) host-builds + connects the declared kind plugins BEFORE `mergeUnifiedDocs`. It is re-entrancy-GUARDED (`inKindConnectPass`): the connect re-loads the project (`LoadConfig`/`ScanAllCandyWithConfigOpts` → `LoadUnified` → the SAME root that contains the kind node), and the nested load skips the pre-pass while `normalizeNodeInto` DEFERS (skips, no error) the not-yet-connected kind node — so the nested scan succeeds and the OUTER pass then has the provider registered + decodes. A declared kind whose provider never connects is WARN-SKIPPED in `normalizeNodeInto` — a loud stderr warning + the node dropped (never a silent drop, never a hard load error), so read-only commands (`box list`, `validate`) still work when a plugin can't build/connect in a degraded environment (a minimal container with no Go toolchain); a command that actually USES the kind fails loudly at that point. Example: `candy/plugin-example-kind` (out-of-process-only). **F5 flat-vs-structural decode** (`runPluginKind`, `provider_kind_invoke.go`): a FLAT kind lands its `OpLoad` body opaquely in `uf.PluginKinds[disc][name]` (F4); a STRUCTURAL kind (capability `Structural=true`, carried by the `structuralKindCarrier` on the grpc/inproc provider) returns a `spec.Deploy` (BundleNode) member tree `runPluginKind` json-unmarshals + folds into `uf.Bundle[name]` — the SAME map `buildBundleNodeInto` populates for a builtin pod, so the folded member goes through the SAME `validateDeploy`. This is the channel that externalizes the structural kind decoders: **`group` is DONE (C2-group — the COMPILED-IN candy/plugin-group serves `kind:group`, Structural:true)** and **the 5 deploy-substrate kinds pod/vm/k8s/local/android are DONE (C2-substrate — the COMPILED-IN candy/plugin-substrate serves all 5, Structural:true; the shared builtin `standaloneKind` + `cue_kind_*.go`-arm removal, all left `spec.KindWords` + the `#Node` disjunction but STAY in `spec.ResourceKinds` so the loader still nests their members)**. Unlike group (a scalar `#GroupInput` value decoded in the plugin from `op.Params`), a substrate value is RICH + core-referencing, so the host uses the F5 `Standalone` channel: `foldSubstrateKind` (`provider_kind_invoke.go`) host-decodes the CANONICAL node via the core loader (`buildBundleNode` deploy → `uf.Bundle`, `decodeStandaloneTemplateJSON` template → `uf.Pod`/`uf.VM`/… — the **TEMPLATE-map fold arm** extending F5's deploy-only fold), validates the value host-side against the KEPT `#<Kind>Value` def (`validateKindValueCUE`, replacing the removed `#Node` arm's closedness — a self-contained plugin schema can't carry the rich value), threads it via `op.Env` (`spec.StandaloneLoad`), and folds the plugin's pure ECHO. **`candy` is DONE too (C2-candy — the LAST structural kind; candy/plugin-candy-kind, COMPILED-IN):** `foldCandyKind` host-decodes via the bootstrap-critical core `candyIsImage` + `buildCandy` (which STAY core — the discovered-candy pre-check calls them directly, so the compiled-in plugin has no bootstrap cycle), validates against the KEPT `#CandyValue` (`validateKindValueCUE`), threads `spec.Box`/`spec.Candy` via the SAME `StandaloneLoad` channel (`candy-image`/`candy-layer` shapes), and folds the echo into `uf.Box`/`uf.Candy`. candy is `Structural:false` (it nests no deploy members) and routes via an explicit `gn.disc=="candy"` host branch. So the `#Node` disjunction now has ZERO built-in arms (`#Node: {...}` — a structural gate only; per-kind value closedness is host-side) and `spec.KindWords` is EMPTY — every authoring kind is plugin-served. **Authored-member INPUT-threading:** the node's AUTHORED resource-member children cannot ride `op.Params` (closed `#<Kind>Input`), so `runPluginKind` PRE-DECODES them host-side via the SAME core recursion the builtin path uses (`buildResourceMemberChildren`, `node_bundle.go` — the ONE member-decode source, called by `buildBundleNode` too, R3) and threads the decoded subtree to `OpLoad` via `op.Env` (`spec.StructuralKindLoadEnv`); the plugin attaches them to its reply, so the reconstructed Bundle is byte-equivalent to the former builtin `group` (proven by `TestExternalStructKind_StructuralDecode` + the `check-group` / `check-structkind` runtime beds). A FLAT kind carrying members is a hard error (no silent drop). The parser gate admits sub-entity children under a recognized external STRUCTURAL kind (`externalKindMayNestMembers`/`recognizedStructuralKind`); core non-resource kinds stay guarded. Example: `candy/plugin-group` (compiled-in structural kind); `candy/plugin-example-structkind` (out-of-process-only witness). |
| `plugin_command_prescan.go` | The EARLY (pre-`kong.Parse`) external-COMMAND-word prescan: `prescanProjectCommandWords` resolves the project dir pre-parse (`projectDirPreParse`: `CHARLY_PROJECT_DIR` → `scanDirFlag` over `os.Args` → cwd) and registers each declared command word so `charly <word>` PARSES; `connectCommandPlugin` is the LAZY connect (LoadConfig → `ScanAllCandyWithConfigOpts` → `loadProjectPlugins` scoped to the one word → `resolve(ClassCommand, word)`), paid only on an actual `charly <word>` invocation |
| `provider_command_external.go` | OUT-OF-PROCESS command dispatch: `collectExternalCommandPlugins` builds a Kong grammar holder per prescanned word with the provider UNconnected (`prov` nil) so the CLI parses; `dispatchExternalCommand` lazy-connects on invocation (`connectCommandPlugin`) and forwards the pass-through args via `Invoke(OpRun, {"args":[…]})`; `NestedCommandProvider` nests an external command under a parent (e.g. `charly check kube`). The BUILTIN command path is `provider_command.go` (`CommandProvider.KongCommand()` + Go `Run`; `builtinCommandBase.Invoke` is in-proc-only). **F8 command compile-in:** `dispatchCommand` (the dispatch entry, called from `main`) routes a parsed dynamic command by PLACEMENT — a COMPILED-IN command candy (registered in-proc as an `inprocProvider`, not a `*grpcProvider`) dispatches IN-PROC via `dispatchInProcCommand` → `Invoke(OpRun, {"args":[…]})`, so the candy's handler runs in charly's own process (native stdio); an out-of-process one keeps `dispatchExternalCommand`/`syscall.Exec`. The dynamic Kong grammar (`externalCommandHolder`) is identical for both placements — only the dispatch transport differs (the command half of placement-invisibility). Example: `candy/plugin-example-command` (dual-placement, compiled-in) | 
| `check_venue.go` | `checkLocalTarget` routes an external deploy host-side (the SAME path `target: local` takes) for `charly check live` / `charly check <verb>`, R3 |
| `sdk/spec/deploy_wire.go` | Deploy IR wire types shared with the plugin SDK: `Scope`, `ReverseOp` (+ `ReverseOpPluginScript`), `InstallPlanView`, `DeployVenue`, `DeployReply`; plus the build-time `BuildEnv` / `EmitReply` for `OpEmit`, and `BuilderResolveInput` + `BuilderResolveReply` (`{Stage, CopyArtifacts, CopyBinary, InlineFragment}`) for the builder `OpResolve` leg |
| `tasks.go:emitPluginFragment` | Renders a plugin verb's BUILD-context Containerfile fragment via `Invoke(OpEmit)` → `spec.EmitReply.Fragment` (placement-agnostic above the registry) |
| `deploykit: EmitBuilderStages` / `EmitBuilderArtifacts` + `generate.go: resolveBuilderStage` | The DETECTION-builder BUILDER leg (C10, relocated to `sdk/deploykit` in #67): for each candy a builder DETECTS, connects the plugin (`ensureBuildersConnected`) + `Invoke(OpResolve)` via the shared `resolveBuilderStage` (`charly/generate.go`, STAYS) → `spec.BuilderResolveReply` (`Stage` pre-main-FROM, `CopyArtifacts`+`CopyBinary` post-main-FROM; cargo's `InlineFragment` splices in `WriteCandySteps` (deploykit)). Renders via the plugins' `kit.BuilderResolve`, NOT an in-core vocabulary. Detection stays host-side (`candyNeedsBuilder`) |
| `deploykit: EmitExternalBuilderStages` / `EmitExternalBuilderArtifacts` + `generate.go: resolveExternalBuilder` | The `external_builder:` BUILDER leg (relocated in #67): emit an out-of-tree `ClassBuilder` candy's multi-stage via the SAME `resolveBuilderStage`/`Invoke(OpResolve)` (minimal input — candy name only); selected by a candy's `external_builder:` field, requires a non-empty `Stage`. `resolveExternalBuilder` STAYS in `charly/generate.go` |
| `build_emit_test.go` | `TestEmitPluginFragment_BuildTimeOpEmit` — the build-time-plugin-execution gate (a non-`ProvisionActor` provider's fragment is spliced via `Invoke(OpEmit)`) |
| `provider_bench_test.go` | The E3 perf go/no-go gate: `TestPerfGate_BuiltinVerbsSkipEnvelope`, `BenchmarkVerbTypedDispatchFork` (0-alloc) vs `BenchmarkVerbEnvelopeMarshal` — builtins skip the JSON `Invoke` envelope; it is paid ONLY out-of-process |

### Dependency & Graph

| File | Purpose |
|------|---------|
| `graph_shim.go` | Thin package-main wrappers (`ResolveBoxOrder()`, `BoxNeedsBuilder()`, `ExpandCandy()`) delegating to the relocated topological sort in `sdk/deploykit/graph.go`; shrinks as callers move to deploykit (the old core `graph.go` is gone) |
| `intermediates.go` | Auto-intermediate image computation (trie analysis). `createIntermediate()` inherits `Distro` and `BuildFormats` **from the parent image first**, falling back to `cfg.Defaults.*` only when the parent is external or empty. Inverting this (defaults winning over the explicit parent) mis-tags every arch-rooted intermediate as `build: [rpm]`, so every layer section keyed on `pac:` emits an empty RUN step (symptom: `arch-ssh-client` ships without `direnv` / `gnupg` / `openssh`). Regression guard: `TestComputeIntermediates_InheritDistroFromParent` uses `defaults.Build=[rpm]` but expects arch-rooted intermediates to come out `[pac]`. |

### Build & Runtime

| File | Purpose |
|------|---------|
| `build.go` | `build` command (sequential image building, retry logic) |
| `merge.go` | `merge` command (post-build layer merging) |
| `shell.go` | `shell` command (execs engine run) |
| `start.go` | `start`/`stop` commands |
| `candy/plugin-status/command.go` | `status` command (the Kong grammar + dispatch; structured table/detail view, live tool probing, `--json`) — relocated from core, reached via the `status-substrate` HostBuild seam |
| `charly/status_collector.go` | the `charly status` collection ENGINE that stays core: `Collector.collectFlat` (substrate fan-out) / `Collector.Single` / `enrichOne` (deploy enrichment) — the pod/local live collectors moved to `candy/plugin-substrate` (P14a), the vm/k8s/android collectors + the pod deploy-enrichment stay here until K5 |
| `commands.go` | `enable`/`disable`/`logs`/`update`/`remove` |
| `service.go` | `service` command (init system service management inside containers) |
| `data.go` | Volume data seeding (`provisionData`, `seedKind`, `SeederHelperImage`) for bind-backed + named-volume targets, driven by `charly config --seed`/`--force-seed` |
| `hooks.go` | Lifecycle hooks (`post_enable`, `pre_remove`) collection and execution |
| `remote_image.go` | Remote image ref resolution, pull-or-build |
| `candy/plugin-vm/vm.go` | VM lifecycle: create, start, stop, destroy, list, console, ssh (the compiled-in `command:vm` plugin) |
| `vm_build.go` | VM disk image builds (qcow2, raw via bootc install) |
| `candy/plugin-vm/vm_libvirt.go` | Libvirt backend: VM operations via session-level libvirt |
| `candy/plugin-vm/vm_qemu.go` | QEMU backend: direct VM operations via qemu-system |
| `sdk/vmshared/smbios_credentials.go` | SSH key injection via SMBIOS/systemd credentials at VM boot |
| `libvirt.go` | Libvirt XML snippet collection and injection |
| `check_endpoint_resolve.go` | The GENERIC host-endpoint reverse-legs the check-verb dispatch serves back to an out-of-process verb over `CheckContextService` (the Uniform API Invariant — class-generic, never a per-verb RPC): `resolveVerbEndpoint(port)` (venue → host-reachable addr — cdp's 9222, vnc's container 5900), `resolveVerbGraphics(kind)` (a VM's `<graphics type='vnc'|'spice'>` via the vm plugin + any qemu+ssh:// tunnel + the vnc socket→TCP bridge + the credential-store ticket), `resolveClusterContext(cluster)` (a kube profile → kubeconfig context via `findK8sSpec`), and `resolveImageLabel(label)` (one raw OCI label — mcp's `ai.opencharly.mcp_provide`). Each serves BOTH the in-proc `runnerCheckContext` and the out-of-proc `checkContextReverseServer`; the plugin PULLS what it needs, so the dispatch carries no per-verb host preresolution and no opaque per-verb payload channel. |
| `candy/plugin-substrate/status_probes.go` *(plugin, not `charly/`)* | The live tool probes (cdp/vnc/supervisord/dbus/charly/wl/sway `HostProbe` + `GuestProbe`) + the `devToolsTab` CDP-tab decode struct, P14a — moved from core (`charly/status_probes.go` + `charly/cdp_preresolve.go`). The cdp endpoint resolution is the `cc.ResolveEndpoint` reverse-leg; the `cdp:` verb (open/list/close/text/html/url/screenshot/click/type/eval/wait/coords/raw + spa-*) + its CDP WebSocket client live out-of-process in `candy/plugin-cdp` (the core's former minimal CDP client `browser_cdp.go` was DELETED when `wl` externalized, so `golang.org/x/net` is an INDIRECT dependency). |
| `vnc_helpers.go` | The host-side VNC support the `cc.ResolveGraphicsEndpoint` reverse-leg needs but the out-of-process plugin cannot reach: `resolveVNCPassword` (the VNC credential store) + `unixToTcpBridge` (the UNIX-socket→TCP bridge for the TCP-only RFB client). The RFB verb (screenshot/click/type/key/mouse/status/passwd/rfb) + its RFC 6143 client live out-of-process in `candy/plugin-vnc`; the venue-aware dual pod/vm resolution (a pod's 5900, or a VM's libvirt VNC display bridged/tunneled) is `resolveVerbGraphics("vnc")` in `check_endpoint_resolve.go`. The separate `charly ssh tunnel vnc` (`ssh.go`) stays in core. |

### Infrastructure

| File | Purpose |
|------|---------|
| `engine.go` | Docker/Podman abstraction, `ResolveBoxEngineForDeploy()` |
| `registry.go` | Remote image inspection (go-containerregistry) |
| `transfer.go` | Cross-engine image transfer |
| `runtime_config.go` | `~/.config/charly/config.yml`, `secret_backend` key, credential maps |
| `network.go` | Shared "charly" container network management |
| `candy/plugin-vm/machine.go` | Podman machine management (rootful VM builds; in the `command:vm` plugin) |

### Configuration

**Key types — user_policy + exclude_distros architecture:**

| Type / Field | File | Purpose |
|---|---|---|
| `DistroDef.BaseUser *BaseUserDef` | `format_config.go` | Pointer to a declared pre-existing uid-1000 account in the upstream base image. Nil when not declared (fedora/arch/debian); set for ubuntu (`{ubuntu, 1000, 1000, /home/ubuntu}`). Inherited via `resolveInherits` so a child distro with no `base_user:` inherits the parent's |
| `BaseUserDef` | `format_config.go` | Four required fields: `Name`, `UID`, `GID`, `Home`. Parsed from the embedded build vocabulary's `distro.<name>.base_user:` |
| `BoxConfig.UserPolicy string` | `config.go:130` | YAML field `user_policy`. Values: `auto` (default) / `adopt` / `create`. Drives the reconciliation switch in `ResolveBox` |
| `ResolvedBox.UserAdopted bool` | `config.go:194` | True when the policy reconciliation adopted a distro's `BaseUser` (User/UID/GID/Home overwritten). Consumed by `WriteBootstrap` in `sdk/deploykit` (relocated in #67) to skip the useradd step |
| `Op.ExcludeDistros []string` | `checkspec.go` | Per-test filter — test runner in `checkrun.go:runOne` skips the check when any of the image's distro tags intersects with this list. Reason reported as `excluded on distro "<tag>"` |
| `TagPkgConfig.Raw map[string]any` | `layers.go` | Captures the full YAML map for a tag section (e.g. `debian:13:`), not just `package:`. Enables `repos:`, `keys:`, `options:` inside tag sections. Read by the generator's install-template emission path |

**Policy reconciliation flow** (`charly/config.go:ResolveBox`, after distroDef loaded):

```go
policy := img.UserPolicy
if policy == "" { policy = c.Defaults.UserPolicy }
if policy == "" { policy = "auto" }
baseUser := (*BaseUserDef)(nil)
if resolved.DistroDef != nil { baseUser = resolved.DistroDef.BaseUser }
userExplicitlySet := img.User != "" || c.Defaults.User != ""

switch policy {
case "adopt":
    if baseUser == nil { return nil, fmt.Errorf(...) }
    // overwrite User/UID/GID/Home
    resolved.UserAdopted = true
case "auto":
    if baseUser != nil && !userExplicitlySet {
        // overwrite User/UID/GID/Home
        resolved.UserAdopted = true
    }
case "create":
    // no-op
}
```

See `/charly-image:image` "user_policy" for the user-facing decision matrix, `/charly-build:build` "base_user:" for the declarative side, and `/charly-build:generate` "writeBootstrap" for the consumer side.

### Existing configuration files

| File | Purpose |
|------|---------|
| `env.go` | ENV merging, path expansion |
| `envfile.go` | `.env` file parsing (`ParseEnvFile`, `ParseEnvBytes`), runtime env var resolution/merging |
| `security.go` | Container security config collection, CLI args generation. Merges `Mounts` from layer security configs |
| `labels.go` | OCI label constants. `LabelDescription` (`ai.opencharly.description`) carries the `LabelDescriptionSet` — each `LabeledDescription` (a `Description` string) plus its `Plan []Step` list; `BoxMetadata`'s `*LabelDescriptionSet` field is populated by `ExtractMetadata` when present |
| `egress.go` | **Egress validation SHIM (M16)** — `ValidateEgress`/`ValidateEgressValue`/`validateTextEgress`/`ValidateXMLEgress` keep their signatures but resolve `verb:egress` + `Invoke(OpValidate, {kind,label,mode,data})` (plain host→plugin dispatch). The validation logic + the egress CUE schemas (package-less defs + the vendored `cloud_config`) moved to the compiled-in `candy/plugin-egress` (`egress-schemas/`), which holds them internally + serves only a trivial Describe schema. The former in-core `egressDef`/`registerVendoredEgressKind`/`egressKindDefs` + the 7 `cue_*egress*.go` registrars were deleted. See `/charly-internals:egress`. |
| `volumes.go` | Named volume collection/mounting |
| `alias.go` | Command aliases (wrapper scripts) |
| `deploy.go` | Per-deployment config overlay, `DeployVolumeConfig`, `ResolveVolumeBacking()`, `saveDeployState()`, `cleanDeployEntry()` (instance-aware provides cleanup) |
| `provides.go` | Env/MCP provides injection, `removeBySource()`, `removeByExactSource()` (instance-specific cleanup), `podAwareMCPProvides()` |
| `enc.go` | Encrypted-volume in-core SHIM + deploy-model (C16a). Keeps `ResolvedBindMount`, the config loader (`loadEncryptedVolume`), the path/probe helpers (`encryptedPlainDir`/`isEncryptedMounted`/`isEncryptedInitialized`/`cipherPopulatedPlainEmpty` — consumed synchronously by the mandatorily-core `ResolveVolumeBacking` + `verifyBindMounts`), `encStatus` (pure probe+print), and the credential passphrase resolution (`resolveEncPassphrase*`/`awaitKeyringUnlockViaPlugin`). `encMount`/`encUnmount`/`encPasswd`/`ensureEncryptedMounts` are thin shims that HOST-PRELIFT the per-volume plan (`encPlanFor`: resolved cipher/plain dirs + init/mounted flags + scope-unit) + the passphrase, then `encExecViaPlugin` resolves verb:enc and Invokes OpExecute. The gocryptfs / `systemd-run --scope --unit=charly-enc-<dir>-<volume>` / fusermount3 / extpass SHELLING lives in `candy/plugin-enc` now, NOT core (`-allow_other` for rootless keep-id, stale-scope retry, all there). The `encMount` all-mounted fast-path (skip passphrase when every volume is already mounted) stays in the shim |
| `devices.go` | The KEPT core GPU/device surface after the GPU/VFIO host-DETECTION externalized to `candy/plugin-gpu` (C11). Holds the embedded detection DATA tables (`devicePatterns`/`gpuRenderVendors`/`pciClassLabels`, kept in core because `charly doctor`'s device report reads `devicePatterns` — threaded to the plugin via the shims, R3) + the pure host-INDEPENDENT env/group helpers `appendAutoDetectedEnv()` (centralizes injection of `HSA_OVERRIDE_GFX_VERSION`/`DRINODE`/`DRI_NODE`), `appendEnvUnique`, `appendGroupsForAMDGPU`, `LogDetectedDevices`, `memlockUnlimited`, `AutoDetectFlags`. The sysfs/exec detection PRIMITIVES moved out (see `gpu_shim.go`) |
| `gpu_shim.go` | The in-core SHIMS for GPU/VFIO host detection (C11): `DetectGPU`/`DetectAMDGPU`/`DetectVFIO`/`DetectHostDevices` (package vars, testability) + `EnsureCDI`/`MemlockLimitBytes`/`VfioGroupAccessible`/`detectAMDGFXVersion` resolve `verb:gpu` and Invoke the COMPILED-IN `candy/plugin-gpu` (OpRun, action-multiplexed `spec.GpuProbeInput`) — the k8sgen/egress resolve+Invoke pattern. The detection RESULT types alias package spec: `type VFIOReport = spec.VFIOReport` (+ `VFIOGpu`/`VFIOPCIDevice`/`DetectedDevices`), so the ~10 consumers (config_image/start/shell CDI-env sites, `charly doctor`, `charly vm gpu`, `charly vm create`, gpu_allocate.go) compile unchanged. In-proc placement keeps `MemlockLimitBytes` reading charly's OWN RLIMIT_MEMLOCK. Wire types: `sdk/spec/gpu_wire.go`. The DRIVER-SWITCH (C9, 1B) now ALSO resolves+Invokes verb:gpu — the gpu_shim.go shims `switchGPUDriverMode`/`gpuSwitchModeTolerant`/`groupInMode`/`currentGPUMode`/`gpuDisplayDriver`/`gpuWedgeDetected`/`ensureCDIRoot`/`gpuSwitchPlan` dispatch the OpRun DRIVER-SWITCH actions (`spec.GpuSwitchInput`/`GpuSwitchReply`); the logic moved into `candy/plugin-gpu` (`switch.go`), the mode/driver consts + wedge sentinel + pure `SelectGPUByVendor`/`NormalizePCIVendor` into `spec`. Auto-allocation (`gpu_allocate.go`) stays core for now (GPU host-seam dropped, revisitable on hardware — the operator-deferred GPU exception, not a K-wave inventory item); the config-coupled GPU-consumer helpers moved to `gpu_imply.go` (still core) |
| `preempt.go` | The HOST side of the resource arbiter after cutover C9: the arbiter LOGIC (`ResourceArbiter`) moved into the COMPILED-IN `candy/plugin-preempt` (verb:arbiter). Core keeps (a) the in-core PROXY — `newResourceArbiter()` returns `*arbiterProxy` whose `ReleaseClaimant`/`clearPoison`/`resourcePoisoned` + the `Lease` + `acquireResourceForClaimant`/`acquireExclusiveForClaimant`/`acquireSharedForClaimant`/`releaseResourceClaim` shims resolve+Invoke verb:arbiter (the generic core→verb registry bridge the core LEASE-LIFECYCLE consumers compile through, R3 — the externalized `command:preempt` CLI reaches verb:arbiter via `InvokeProvider` instead, owning the lease-table formatting itself), and (b) the 7 arbiter HOST-SEAM impls (`gatherPreemptibleHolders`/`holderRunning`/`holderStop`/`holderStart`/`gatherResources`/`holderAddrFor`/`lookupVMClaimant`/`waitStoppedHost`) the arbiter calls back over the ALWAYS-SERVED `ExecutorService.HostArbiter` reverse leg (stateless, so inert on every non-arbiter channel). Persisted + seam wire types live in `sdk/spec/arbiter_wire.go`; the ledger I/O + poison + liveness + mode-math live IN the plugin (`arbiter.go`/`arbiter_support.go`) |
| `arbiter_host.go` | The HOST handler for the C9 `ExecutorService.HostArbiter` reverse channel: `arbiterHostServer.dispatch` runs the 7 arbiter host-seams, projecting `gatherPreemptibleHolders` → `[]spec.HolderDescriptor` + `gatherResources` → token→vendor, folding the stop seam's wait (`holderStop`+`waitStoppedHost`), and routing switchMode/ensureCDI to the gpu shims |
| `tunnel.go` | The RESOLUTION half of the tunnel subsystem (C16b externalization): the wire types `TunnelConfig`/`TunnelPort`, the pure helpers `schemeTarget`/`tailscaleFlag`/`isTCPFamily`/`ValidPublicPorts` (shared with the quadlet emitter), the config-path helpers `tunnelConfigDir`/`tunnelConfigPath` (referenced by quadlet.go's `generateTunnelUnit`), and the resolution `ResolveTunnelConfig`/`TunnelConfigFromMetadata`/`parseHostPorts`/`buildPortMapping`/`resolveProto`. The EXECUTION leg (tailscale serve/funnel + the cloudflared lifecycle) externalized to `candy/plugin-tunnel` — see `tunnel_plugin.go` |
| `tunnel_plugin.go` | The CORE adapter for the EXTERNALIZED tunnel execution leg (C16b, the welded-verb pattern mirror of `credential_plugin.go`): the `TunnelStart`/`TunnelStop`/`cloudflareTunnelSetup` seams forward a resolved `TunnelConfig` to `verb:tunnel` as a `{method, config}` `plugin_input` envelope over the Invoke registry (`tunnelProvider` is registry-first so the compiled-in provider resolves project-lessly, then falls back to `connectPluginByWord` for baked/source). The tailscale serve/funnel + cloudflared lifecycle live in `candy/plugin-tunnel/` (compiled into charly via `compiled_plugins:`, or out-of-process); `verb:tunnel` also serves a creds-free `plan` dry-run returning the argv it WOULD run (box/fedora's `check-tunnel-pod` bed R10) |
| `quadlet.go` | Quadlet .container file generation, `Secret=` directives |
| `credential_plugin.go` | The CORE adapter for the EXTERNALIZED credential store (C2 dep-shed removed `go-keyring`; the godbus dep-shed removed `godbus` too — `charly/go.mod` links neither): `CredentialStore` interface, `ResolveCredential()`, `DefaultCredentialStore()` (→ `pluginCredentialStore`), `resolveSecretBackend()`, `credentialHealth()`, `pluginCredentialStore.awaitUnlock` + the `credentialAwaiter` seam (enc.go's `source=locked` keyring wait — RPCs `verb:credential await-unlock`, the godbus PropertiesChanged subscription running IN the plugin), the `setDefaultCredentialStoreForTest` seam. Every method forwards to `verb:credential` (served out-of-process by `candy/plugin-secrets`, or the baked `/usr/lib/charly/plugins` binary). The store backends + the keyring-unlock waiter + the `charly secrets` CLI + GPG `.secrets` surface live in `candy/plugin-secrets/` now, NOT core. **Generic host-adapter seam (F7/C7):** `callCtx` connects via `connectPluginByWord(ClassVerb, "credential")` — the ONE on-demand connect for a verb word that appears in NO plan step. `vm_plugin_client.go` (`invokeVmPluginEnv` → `verb:libvirt`) and `k8s_plugin.go` (`invokeKubePlugin` → `verb:kube`) now route through the SAME seam (`connectPluginByWordRef` adds an optional canonical-ref fallback for a project whose closure references the plugin candy nowhere, e.g. a `box/<distro>` VM bed) — the bespoke `ensureVmPluginConnected` sync.Once + kube's bare `ResolveVerb` were deleted (R3) |
| `secrets.go` | Container secret collection from labels, Podman secret provisioning, `SecretArgs()`, `generateAndStoreSecret`, the interactive `promptPassword` (a deploy-time operator prompt) |

### Remote Layer Refs

| File | Purpose |
|------|---------|
| `refs.go` | Remote ref types, parsing, cache management. `CHARLY_REPO_OVERRIDE` (`RepoOverrideEnv`) Go-`replace`-style local-tree override (`repoOverrideDir`). `selfSuperprojectOverridePair(dir)` derives the bed project's OWN superproject override (`git rev-parse --show-superproject-working-tree` → `rootRepoIdentity`); `mergeRepoOverrides` appends it after operator entries (operator wins). The check-bed setup op (in `candy/plugin-check/bed_run.go`, over the `check-bed` host seam) auto-applies it so a `box/<distro>` bed tests LOCAL parent-repo candies, never the pinned remote — the candy-ref analogue of auto `--dev-local-pkg`. Tests: `repo_override_test.go`. |
| `refs_git.go` | Git operations: clone, resolve ref, tag resolution |

### Declarative Testing

Implements the check gathering, validation, and host seams behind `charly check
live` / `charly check box` (whose CLI now lives in the `command:check` plugin
`candy/plugin-check`) and the `ai.opencharly.description` OCI label. User-facing
authoring, verb catalog,
runtime variables, and charly.yml overlay rules live in `/charly-check:check` — this
section is the Go-implementation map.

| File | Purpose |
|------|---------|
| `checkspec.go` | `Op` (the `= spec.Op` generated param alias — no hand struct; `Op.Kind()` is a package-`spec` method) — the unified verb vocabulary, the former Task + Check merged into one; `Kind()` enforces exactly-one verb. Built-in verbs (file/port/command/http/package/service/process/dns/user/group/interface/kernel-param/mount/addr/matching) plus the live-container verbs — ALL out-of-process now (`wl`/`cdp`/`vnc`/`dbus`/`kube`/`adb`/`appium`/`spice`/`mcp`/`record`/`libvirt`), dispatched via `invokeVerbProvider` to their plugin candies (all still verb words on core `#Op`; `wl` was the LAST compiled-in live verb). **`Status` on the http verb is a plain `int`** — not a MatcherList. One expected code per test; no `[200, 302]` list shorthand. `Matcher` + `MatcherList` with custom YAML **and** JSON unmarshalers for scalar/list/map shorthand — symmetry between charly.yml authoring and hand-crafted OCI labels. The plan step types travel in `LabelDescriptionSet` (the `ai.opencharly.description` label carries a `Plan []Step` field per `LabeledDescription`). Extended `${NAME[:arg]}` matcher (in `ExpandTestVars`) — backward-compatible widening of `taskVarRefPattern` in `tasks.go`. **No bash-style defaults**: `${VAR:-fallback}` is unsupported; only `${IDENT}`. `ExpandTestVars`, `TestVarRefs`, `IsRuntimeOnlyVar`, `Op.ExpandVars`. |
| `checkvars.go` | `ResolveCheckVarsBuild` / `ResolveCheckVarsRuntime`. `InspectContainer` is a swappable package-level `var` (test-friendly pattern matching `InspectLabels` in `labels.go`). Maps `podman inspect` output into `HOST_PORT:<N>`, `VOLUME_PATH:<name>`, `VOLUME_CONTAINER_PATH:<name>`, `CONTAINER_IP`, `CONTAINER_NAME`, `ENV_<NAME>`. |
| `checkrun.go` | `Runner`, `Executor` interface, `ContainerExecutor` (via `podman exec`), `ImageExecutor` (via `podman run --rm`). The result model — `CheckStatus`/`CheckResult`/`StepResult` + the pass/fail/skip verdict + the text/JSON/TAP/JUnit formatters — lives in `sdk/kit` (`kit.Status`/`kit.CheckResult`/`kit.StepResult`/`kit.FormatStepResults*`, P5-unit-2); `checkrun.go`/`description_run.go`/`kit_aliases.go` carry the package-main aliases. Per-verb dispatch for `file`/`port`/`command`/`http`. Matcher evaluation: `matchOne` + `matchNumeric` (`lt`/`le`/`gt`/`ge`). `validMatcherOps` allowlist kept in lockstep with the runner switch by `TestMatcher_AllowlistRunnerSync`. |
| `checkrun_verbs.go` | Dispatch for the remaining verbs: `package` (rpm/dpkg/pacman), `service` (supervisorctl + systemctl), `process` (pgrep), `dns` (host-side `net.LookupIP` or in-container `getent`), `user`/`group` (getent passwd/group), `interface` (`ip -o addr show` + MTU), `kernel-param` (`sysctl -n`), `mount` (`findmnt`), `addr` (host-side `net.DialTimeout` or in-container `nc -z`), `matching` (pure in-process value matching). **`resolvePackageName(c, distros)`** implements the distro-aware package-map: when `Check.PackageMap` is non-empty, the first entry in `Runner.Distros` that matches a key wins; otherwise `Check.Package` is used as-is. Covered by `TestResolvePackageName` (6 sub-cases including empty-map fallback, first-matching-tag-wins priority, and empty-string-map-value fall-through). `Runner.Distros` is populated from `meta.Distro` wherever a `Runner` is built — the `check_cmd.go` live-gather engine and the `command:check` plugin's box/feature/harness runners. |
| `check_members.go` | **Cross-deployment probing** — a DRIVER deployment probing a SEPARATE SUBJECT. `liveTargetResolver` is the venue-from-position TargetResolver for `charly check live` + beds (resolves a driver/member via `resolveCheckVenue` + `ResolveCheckVarsRuntime`); wired into the `CheckLiveCmd` live-gather engine (pod path) AND `runVm` (VM path). The unified `${HOST:member}` / `${HOST:member:port}` address var (`applyHostVars` → `collectHostRefs` → `resolveHostVars`) is pre-resolved into `Runner.HostVars`, overlaid by `effectiveEnv` onto whatever resolver is active (primary / venue-swapped / harness — one injection point). `${HOST:member}` (no `:port`) = the subject's `charly-<member>` container DNS (via `resolveContainer`, which also verifies running); `${HOST:member:port}` (with `:port`) = host-reachable `resolveCheckEndpoint`. Registered runtime-only in `checkspec.go` `runtimeOnlyVarPrefixes`. |
| `bundle_members.go` | **Sibling-member lifecycle** — venue-from-position members (shared by check + deploy — R3). `foldMembers` registers each tree-position `BundleNode.Members` entry as a top-level addressable Bundle entry (`MemberOf` set, disposability inherited); `validateMembers` enforces dot-free + valid-target member keys. `bringUpMembers` / `tearDownMembers` shell out (via the package-var `runCharlySubcommand`) to `charly config`+`charly start` (pod members) / `charly bundle add`+`del` (other), invoked by `BundleAddCmd`/`BundleDelCmd` (operator) AND the bed runner — `candy/plugin-check/bed_run.go` drives `bringUpMembers`/`tearDownMembers` (kept core) over the `check-bed` seam's `members-up`/`members-down` ops (pod + VM paths). Members are excluded from `bedCheckLiveRefs` (instruments, never check-live'd). |
| `checkrun_charly_verbs.go` | Shared host-side helpers for the EXTERNAL live-container verbs: `resolveCheckApk` (anchors an adb/appium `apk:` fixture to its authoring candy's source tree, host-side, before the marshalled `Op` crosses to the plugin) + the `noVmDisplayDeviceErr` skip sentinel (the spice/vnc VM-display N/A skip). Every live-container verb (`wl`/`cdp`/`vnc`/`dbus`/`kube`/`adb`/`appium`/`spice`/`mcp`/`record`/`libvirt`) is an EXTERNAL out-of-process plugin dispatched via `invokeVerbProvider` with the full `Op` (`wl`/`record`/`dbus` are EXEC-based: the provider drives the venue over the `DeployExecutor` reverse channel; `cdp`/`vnc` dial a host-pre-resolved endpoint). The EXEC-based verbs' (`wl`/`record`/`dbus`) shared boilerplate lives in the SDK/kit, ONE copy each (R3): `sdk.RunArtifactValidators` (post-run artifact validators) + `sdk.MatchAll` (the matcher pipeline) + `sdk.ResultJSON` (the `{status,message}` reply) + `sdk.CheckRequiredModifiers` (the required-modifier check) + the `*sdk.Executor` venue methods `VenueCapture`/`VenueHasTool`/`VenueRunSilent`, with `kit.ShellQuote`/`kit.TrimPreview` the pure quoter/preview; each plugin keeps only its per-verb `requiredModifiers` map + `modifierZero`. The nested-CLI argv contract a plugin imports (`kit.MethodSpec` + the `kit.Pos*` builders) lives in `sdk/kit/methodspec.go`. |
| `candy/plugin-mcp` (mcp resolution) | The `mcp:` verb resolves its OWN context via the reverse-legs (resolve.go): `cc.ResolveImageLabel("ai.opencharly.mcp_provide")` for the declared servers, then `{{.ContainerName}}` substitution + `spec.PodAwareMCPProvides` localhost rewrite + pick + `cc.ResolveEndpoint` to map the container port → host address. The MCP CLIENT (the go-sdk dial + the 7 methods `ping`/`servers`/`list-tools`/`list-resources`/`list-prompts`/`call`/`read`) lives here too, beside the SERVER (`serve.go`, `command:mcp`); charly's core links NO MCP SDK — its host half is the `charly __cli-model` seam (`cli_model_cmd.go`). |
| `cli_model_cmd.go` | **`charly __cli-model`** (hidden machinery) — emits charly's ASSEMBLED Kong command tree (the core CLI struct + the builtin command-provider grammar) as an `sdk.CLIModel` JSON document on stdout: the host half of the EXTERNALIZED MCP server. `candy/plugin-mcp` (`command:mcp` — the externalized `charly mcp …` CLI; `serve.go`) fork/execs it at startup (`fetchCLIModel`, deliberately with NO project prefix — the model needs no project), registers one MCP tool per model leaf (`cliLeafToTool`/`argToSchema`, `additionalProperties: false`), annotates/filters mutating tools via its `mcpDestructivePaths` allowlist (`--read-only` skips registering them), and executes each tool call as a `charly <path> <args…>` SUBPROCESS (`makeToolHandler` → `argvFromJSON` → `forkCharly`) carrying a managed project prefix (`computeProjectPrefix`: charly.yml in cwd → none; `--no-default-repo` → none, project tools error at call time; else `--repo default`) with `childCharlyEnv` stripping `CHARLY_PROJECT_DIR`/`CHARLY_PROJECT_REPO` so the prefix stays authoritative. Core links NO MCP SDK — the fork/exec design replaced the former in-process server wholesale. Test coverage: `cli_model_cmd_test.go`. Full reference: `/charly-build:charly-mcp-cmd`. |
| `main_dir_test.go` | Integration tests for the `-C` / `--dir` / `CHARLY_PROJECT_DIR` global: spawns a freshly-compiled `charly` binary from `/tmp` with a scratch project, verifies all three flag forms make `charly box list boxes` resolve the scratch `charly.yml`. Error cases: missing dir, file-not-dir. |
| `local_image.go` | `resolveLocalImageRef(engine, input)` — test-mode-only image resolution that never reads `charly.yml`. Full refs pass through with a `LocalImageExists` check; short names match against `ListLocalImages()` output using label-preferred matching (`ai.opencharly.box=<name>`) with a repo-name trailing-component fallback. Returns `ErrImageNotLocal` on no-match so `FormatCLIError` renders the "charly box pull / charly box build" recommendation. Used to keep `charly check box` purely OCI-labels-driven — short names resolve against local podman storage, never `charly.yml`. |
| `description_collect.go` | `CollectDescriptions(cfg, layers, imageName) *LabelDescriptionSet` walks the base-image chain — mirror of `CollectHooks` in `hooks.go:18-68` — with a visited-image guard so pathological cycles reported by `validateBoxDAG` can't hang the collector. Bucketizes plan steps into `candy`/`box`/`deploy` by source + context, stamps `Origin` for reporting. `MergeDeployDescriptions(baked, local)` implements id-based replace, append, and `{id: X, skip: true}` disable semantics. |
| `check_cmd.go` | The CLI-FREE live-check GATHER engine: `checkLiveGather` / `checkLiveVM` / `checkLivePod` / `checkLiveLocal` / `checkLiveGroup` / `resolveVmTarget` / `loadVmCheckPlans`, carried by the KEPT `CheckLiveCmd` struct — now a pure engine carrier reached by the `host_build_check_run.go` "live" seam, not a kong command. The gather resolves the container (`resolveContainer` → `containerImageRef` → `ExtractMetadata`), loads the `BundleNode.Plan` overlay (`MergeDeployDescriptions`), resolves runtime vars (`ResolveCheckVarsRuntime`), populates `Runner.Box`/`Instance` so the out-of-process live-container verbs can resolve the target container, and runs the plan. The `charly check` CLI — its command tree, the `box`/`live`/`run`/`feature` verbs, the check-run management subcommands, and the `charly check box` disposable-container flow — lives in the compiled-in `command:check` plugin `candy/plugin-check`. |
| `check_runner_cmd.go` | Now holds ONLY `scorePodTargetEntry` — the pod-target-disposability read consulted by the check-config seam (`host_build_check_config.go`). The check-run management Cmds and the orchestrator preflight (`runWithPhaseResync` — the harness-sandbox restart + credential sync + `charly check run-local` dispatch) moved to the `command:check` plugin `candy/plugin-check`. |
| `check_runner_live.go` | `RunCheckLive` — the "score" mode body reached via the `host_build_check_run.go` "score" seam, invoked at iter end by the `command:check` plugin's harness scorer. Buckets `check:` steps by `pod:`, resolves chains via `ResolveDeployChain` for dotted paths, dispatches to the right `DeployExecutor`. The plugin's self-evaluate path (the AI-side mid-iter sanity check) drives the same seam. |
| `check_image_preflight.go` | `ensureScoreImages` — the "preflight" mode body (reached via the `host_build_check_run.go` seam): walk the plan's per-step-venue images + the target image, dedup, ensure each present in local podman before a host-target harness run. |
| `host_build_check_run.go` | The "check-run" host-builder the compiled-in `command:check` plugin drives — `spec.CheckRunRequest{mode}` ∈ box / live / feature-box / feature-live / **score** (→ `RunCheckLive`) / **preflight** (→ `ensureScoreImages`). The gathering + registry verb dispatch + venue construction stay host-side; the plugin owns CLI-parse + formatting + the exit code via `sdk.ExitCodeError`. |
| `host_build_check_bed.go` | The op-discriminated "check-bed" host SESSION seam (setup / members-up / members-down / wait-ready / teardown) — the bed's lock / preempt-lease / repo-override + deploy-config env lifecycle the compiled-in bed runner cannot hold across a process boundary. `setup` returns the BedDescriptor (`spec.CheckBedReply`, incl. `BedDomain` #33, group `Members`, `LocalChildKeys`) the kind-blind plugin drives the R10 sequence from. Transitional (K5). |
| `host_build_check_config.go` | The "check-config" projection seam — the check-project reads the harness makes (bed-vs-iterate classify, sandbox class, pod-target disposability, resolved iterate config, include-expanded plan, kind:agent catalog) that a plugin (a separate module) cannot LoadUnified for. Transitional (K1). |
| `check_bed_run.go` | The KEPT bed-seam helpers the `check-bed` session drives: `bedVmDomains`/`acquireVmDomainLock` (per-deploy domain locks, #33), `persistBedDeployOverrides`, `deployNestedLocalChildren`, `bedCheckLevel`, `waitForVmSshReady`/`waitForContainerReady` — shared with `bundle_add_cmd`. The bed-run ORCHESTRATION itself moved to `candy/plugin-check/bed_run.go` (driven over this seam + `HostBuild("cli")`). |

**Related skill**: `/charly-check:check` is the authoring-facing reference.

## Go Module Info

- Go version: 1.26.0
- Key dependencies: `kong` (CLI), `go-containerregistry` (OCI), and `github.com/opencharly/sdk` (the plugin contract module — required with `replace github.com/opencharly/sdk => ../sdk` for in-tree resolution). The credential store's `go-keyring` (Secret Service API) is NOT a core dependency — it links only into the out-of-process `candy/plugin-secrets` plugin (the C2 dep-shed)
- Module path: `charly/go.mod`

## Common Workflows

### Add a New CLI Command

1. Define command struct in appropriate file (or new file)
2. Add to CLI struct in `main.go`
3. Implement `Run()` method
4. Add tests in `*_test.go`
5. Build and test: `cd charly && go test ./... && go build -o ../bin/charly .`

### Add a New Validation Rule

A host-natural check that needs the raw loader goes in `charly/validate.go`; the
per-kind/op/candy/graph rule engine lives in the compiled-in `command:box` plugin
(`candy/plugin-box`) over the resolved-project envelope — add per-entity/op rules
there.

### How to change the charly.yml schema (CUE is the single source of truth)

CUE (`sdk/schema/*.cue` — the sdk contract module) is the SOLE author-of-record
for the `charly.yml` ingress schema; the Go param structs in `sdk/spec` and the
reserved-word vocabulary are GENERATED / DERIVED from it (see "CUE is the single
source of truth"). The recipe:

1. **Edit CUE only.** Add or change the field, kind, verb, or method enum in
   `sdk/schema/*.cue`. A param-struct field is just a CUE field; a new KIND is a new
   `#Node` arm + a per-kind `#Def`; a new VERB is a field on `#Op` (+ a
   `#*Method` enum if it carries methods). Keep the `#Def` CLOSED (closed by
   DEFAULT — that is what catches a misspelled field); for two mutually-exclusive
   fields use a disjunction applied with `&` (`#Box: {…} & ({from?: _|_} |
   {base?: _|_})`), NEVER an embedded `matchN`, which silently disables
   closedness (the comments in `box.cue` / `candy.cue` / `vm.cue` document this).
2. **Annotate for Go with `@go()`.** A multi-word field → `@go(GoName)` (wire key
   preserved); a named scalar you want as a plain Go `string`/`map` →
   `@go(,type=string)` merged as `@go(GoName,type=string)`; a pointer / tri-state
   field → `@go(GoName,optional=nillable)` (→ `*T`) or `@go(GoName,type=*int|*bool)`;
   a disjunction field → `@go(GoName,type=YourUnionType)` and hand-write that
   union in `sdk/spec/union_types.go`; a never-authored field → `@go(-)`.
   NOTE: def-level `@go(CharlyName)` is BROKEN in cue v0.16.1 (it dangles the
   referencing fields) — expose a charly type NAME via a Go alias in
   `sdk/spec/charly_names.go` (`type BoxConfig = Box`) instead.
3. **Regenerate: `task cue:gen`** (in the sdk repo, or via the superproject task
   which chains the sdk generation first, then the per-plugin params loop). It
   runs `cue exp gengotypes` into `sdk/spec/cue_types_gen.go`, the companion
   `sdk/internal/schemagen` into `sdk/spec/vocab_gen.go` + `sdk/spec/version_gen.go`,
   and the principled yaml-tag retag transform (both over the `sdk/schemaconcat`
   concatenation). NEVER hand-edit the generated files (they carry the
   `Code generated … DO NOT EDIT` banner).
   `TestGenReproducible` (`sdk/spec/gen_repro_test.go`) fails if committed ≠ fresh.
4. **Bind behavior.** A new GENERIC install-VERB (a kernel primitive — rare) adds
   ONE `VerbCatalog` handler in `charly/reserved_registry.go` binding the reserved
   word to its generated param type; the startup
   `checkVerbBijection(VerbCatalog, spec.OpVerbs, spec.AuthoringVerbs)` gate panics
   fast (and fails `TestReservedWordRegistry_*`) if CUE and the registry disagree.
   A new KIND is NOT a core edit — it is a PLUGIN (per the kernel/plugin boundary
   law): it serves its own schema over Describe and is gated by
   `checkKindProviderBijection(spec.KindWords)` (`charly/provider_kind.go`) against
   `spec.KindWords` (empty; every authoring kind is plugin-served). See
   `/charly-internals:plugin` "The kernel/plugin boundary law".
5. **The drift gates (keep them all green).** There is no `spec_parity_test.go`;
   field parity is enforced three ways. (a) The **compile-time alias surface** —
   every package-main param type is a `type X = spec.X` alias
   (`sdk/vmshared/spec_aliases.go`, re-exported via `charly/vmshared_aliases.go`),
   so a hand-referenced field that no longer has a
   matching spec field (name + wire-key + type) FAILS the build at that surface.
   (b) `TestGenReproducible` proves the generated files match a fresh `task
   cue:gen`. (c) The reserved-word bijection gate proves the kind/verb/method
   wiring matches CUE. New kind also needs its `sdk/schema/<kind>.cue` `#<Kind>` def
   (reusing the shared defs in `_common.cue`) + a one-line `cue_kind_<kind>.go`
   `registerCueKind` registration + a corpus-test entry
   (`cue_kinds_corpus_test.go`).
6. **Schema-version bump ONLY on an authored WIRE-key change.** Only if the
   change alters an authored WIRE key (the YAML users write) is it a FORMAT
   change: then it is CROSS-REPO — bump `#SchemaVersion` in
   `sdk/schema/version.cue`, run `task cue:gen` (which regenerates the
   `SchemaVersion`/`SchemaFloor` consts in `sdk/spec/version_gen.go` that
   `kit.LatestSchemaVersion()` parses), land + tag the sdk repo, then in the
   superproject bump the sdk submodule and append the matching entry to the
   declarative migration table (`candy/plugin-migrate/migrations.cue` — the TABLE lives in
   the compiled-in `command:migrate` plugin) per `/charly-build:migrate`. A pure
   Go-identifier change via `@go()` is NOT a format change (wire key preserved) —
   do NOT bump the schema version.
7. **Guards (all must pass):** `cd charly && go test ./...` (reproducibility +
   bijection + corpus + closedness + embedded-defaults via
   `validateVocabularyCollections` / `TestEmbeddedDefaults_SchemaConformance`) +
   `charly box validate` on the repo and every `box/<distro>` submodule + the R10
   bed gate.

Do NOT reintroduce a hand-maintained vocab list, a per-verb dispatch switch, or
a hand-written param struct — they are generated / derived from CUE now. Do NOT
use `cue get go` (that is the Go→CUE direction; CUE is the source here). The
ingress validation recipe is owned by `/charly-build:validate`; the egress
analog is the "Adding a new egress schema" recipe in `/charly-internals:egress`.

### Debug a Build Issue

```bash
# Generate Containerfiles without building
bin/charly box generate

# Inspect generated output
cat .build/<image>/Containerfile

# Validate configuration
bin/charly box validate

# Inspect resolved image config
bin/charly box inspect <image>
```

### Intermediate image cache invalidation

`charly box build` auto-generates intermediate images (e.g., `ghcr.io/opencharly/charly-fedora-2-dbus-nodejs`) that bundle the `charly` layer plus common layers for cache reuse across many downstream images. These intermediates are aggressively podman-cached. Updating `candy/charly/bin/charly` does invalidate the COPY step inside the intermediate, but if the intermediate tag already exists locally, `charly box build` may reuse it without re-running the build chain. To force a fresh binary propagation after a manual `bin/charly` update:

```bash
charly clean --invalidate 'charly-fedora-2*'
charly box build <image>
```

This also interacts with the dual-path gotcha documented in `/charly-tools:charly`: `bin/charly` (repo-root, used by host-side invocations) and `candy/charly/bin/charly` (what the `charly` candy actually copies into images) must stay in sync. The canonical `task build:charly` path does both; a manual `go build -o bin/charly ./charly` needs an explicit `cp bin/charly candy/charly/bin/charly` follow-up.

## Implementation insights

These are hard-won lessons that shape the Go-side architecture. They're not obvious from reading the source cold; skim this list before making structural changes.

### Kong flag-namespace collision

Top-level flags and subcommand flags share one global namespace. Declaring the same flag on both `CLI` (`charly/main.go`) and a subcommand struct panics with `duplicate flag --<name>` at Kong parse time. Resolution: drop the subcommand flag entirely and let users pass the top-level form; only keep subcommand flags when they have no top-level twin. (The motivating instance — `--repo` on the in-core mcp-serve command — moved out with the server: `candy/plugin-mcp/serve.go`'s `McpServeCmd` now parses inside the plugin's own grammar, where `--no-default-repo` remains a serve-local flag.)

### Env-var proxy for parent-flag detection

When code runs where it cannot reach the parsed parent `CLI` struct, read the flag's bound env var instead: Kong populates env vars from flags, so `os.Getenv("CHARLY_PROJECT_DIR")` is a reliable proxy whether the user passed `--dir` or the env var. The live instance is `projectDirPreParse` (`charly/plugin_command_prescan.go`) — the pre-`kong.Parse` command-word prescan resolving the project dir. (The externalized MCP server no longer needs the proxy: `candy/plugin-mcp/serve.go` computes a managed `--dir`/`--repo` child-argv PREFIX per tool call — `computeProjectPrefix` — and `childCharlyEnv` strips `CHARLY_PROJECT_DIR`/`CHARLY_PROJECT_REPO` from the child env so the prefix stays authoritative.)

### `yaml.v3` Node API is the single reason edits preserve comments

Unmarshal-to-value + re-marshal scrambles comments, key order, and node styles. Every `charly.yml` editor in the authoring surface (`kit.SetByDotPath` in `sdk/kit/yaml.go`; `kit.AddBox` in `sdk/kit/scaffold.go`; `addCandyToBox` / `removeCandyFromBox` in `candy/plugin-authoring/authoring_edit.go` (P14b — moved from core); `appendCandyPackages` in `candy/plugin-candy/command.go`) navigates `*yaml.Node` trees directly and only serializes with `yaml.Marshal(root)` at the very end. Tests (`sdk/kit/yaml_test.go`, `charly/scaffold_project_test.go`, `candy/plugin-authoring/authoring_edit_test.go`) explicitly verify that leading file comments, sibling keys, and per-key inline comments all survive round trips.

### Scalar-to-sequence upgrade (scaffold `package:` null)

The layer scaffold writes `rpm:\n  packages:\n  # Add RPM packages here\n` — the value of `package:` parses as scalar-null, not a sequence. Naively calling `candiesNode.Content = append(...)` silently no-ops. `appendCandyPackages` (`candy/plugin-candy/command.go`) checks `pkgsNode.Kind != yaml.SequenceNode` and upgrades in place (`Kind = yaml.SequenceNode; Tag = "!!seq"; Value = ""; Content = nil`). This preserves the key+comment association on serialization. Any other "upgrade a null scalar to a collection" path needs the same pattern.

### Path-traversal guard on the `box write` / `box cat` escape hatch

`resolveProjectFile(projectDir, relPath)` in `candy/plugin-authoring/authoring_edit.go` (P14b — moved from core `charly/scaffold_cmds.go`) is the single safety boundary for agent-driven file writes. It rejects absolute paths, calls `filepath.Clean`, then uses `filepath.Rel` + a prefix check to confirm the result stays inside the project root. Any future "free-form file read/write" verb must go through the same helper.

### Project-dir resolver is a two-step resolver, not one

`charly/main.go` resolves the project dir in two steps: `--repo` resolves to a cache path first (`charly/main_repo.go` calls `ResolveProjectRepo` → `EnsureRepoDownloaded`), then falls through into the `os.Chdir(cli.Dir)` block. The two paths are mutually exclusive (fast-fail if both are set). Downstream code just reads `os.Getwd()` — no per-command plumbing. Tested in `charly/main_repo_test.go` (hermetic via `CHARLY_REPO_CACHE` pre-seeding).

## R9 — deployed binary matches source; runtime deps live in the PKGBUILD

CLAUDE.md R9, operationalized for the `charly` toolchain:

- **Syncing source does not rebuild the binary.** Syncthing / git / rsync move
  *source* between hosts. After pushing code, rebuild on the target
  (`task build:charly`) and verify `charly version` matches what you built — if the
  version is old, the fix under test isn't really under test. The freshness
  guard (above) catches a stale `/usr/bin/charly` against newer `charly/*.go`, but the
  version check is still the explicit proof.
- **Every runtime OS dependency goes into `pkg/arch/PKGBUILD` `depends=`** —
  the single source of truth (`nc`, `socat`, `xorriso`, `qemu-guest-agent`, …);
  the `pkg/fedora` / `pkg/debian` packaging mirrors it. A manual install on one
  host is a bug report disguised as a fix — it won't survive a fresh install on
  a synced host.

The verification side (checking the deployed binary + deps on a live target)
is `/charly-check:check` Standards 7–8; the dual-path `bin/charly` ↔
`candy/charly/bin/charly` gotcha is above and in `/charly-tools:charly`.

## Style Guide

- All logic belongs in Go. Taskfiles are only for bootstrap (building charly).
- Taskfiles for bootstrap only, Go for all other logic.
- Test files alongside source files (`foo.go` -> `foo_test.go`).

## Cross-References

- `/charly-internals:generate-source` — Understanding generated Containerfiles + deep dive on the task emission pipeline (`charly/tasks.go`).
- `/charly-image:layer` — **Canonical author-facing reference** for the task verb catalog that `charly/tasks.go` implements.
- `/charly-build:validate` — Validation rules and error handling (`validateCandyTasks` in `candy/plugin-box/validate_rules.go`).
- `/charly-build:build` — Using the built CLI.
- `/charly-check:check` — Author-facing reference for the declarative-testing feature that `checkspec.go` / `checkvars.go` / `checkrun.go` / `checkrun_verbs.go` / `checkrun_charly_verbs.go` / `description_collect.go` / `check_cmd.go` / `local_image.go` / `check_endpoint_resolve.go` (the host-endpoint reverse-legs) implement. (Op-level check validation moved out of core to `candy/plugin-box/validate_check.go`.)
- `/charly-build:charly-mcp-cmd` — Author-facing reference for both (a) the declarative `mcp:` client check verb (method catalog, URL-rewrite behavior, port-publishing gotcha, transport dispatch — served out-of-process by `candy/plugin-mcp`, which resolves its endpoint via the `check_endpoint_resolve.go` reverse-legs) and (b) the `charly mcp serve` server (externalized to `candy/plugin-mcp` `command:mcp`: one tool per CLI leaf, auto-generated from the `charly __cli-model` reflection seam, destructive-hint + `--read-only` filter, Streamable-HTTP + stdio transports, auto-fallback to `opencharly/charly` — pair with `cli_model_cmd.go` + `main_repo.go` + `box_fetch_reentry.go` + `candy/plugin-authoring` + `sdk/kit/yaml.go` above).
- `/charly-coder:charly-mcp` — The candy that deploys `charly mcp serve` inside a container: bind-mount volume NAME `project` at the container PATH `/workspace`, `CHARLY_PROJECT_DIR=/workspace` so build-mode MCP tools (`box.list.boxes`, `box.inspect`, etc.) reach `charly.yml` from outside the project checkout — or auto-fall back to `opencharly/charly` when `/workspace` is empty (the fallback fires on absence of charly.yml, not absence of CHARLY_PROJECT_DIR).
- `/charly-check:wl`, `/charly-check:cdp`, `/charly-check:vnc`, and `/charly-check:dbus` are out-of-process verbs served by `candy/plugin-wl` / `candy/plugin-cdp` / `candy/plugin-vnc` / `candy/plugin-dbus` (cdp/vnc resolve their endpoints via the `check_endpoint_resolve.go` reverse-legs; `wl`/`dbus` are EXEC-based and reach the venue over the executor).
- Source: `charly/` directory (~304 source + ~294 test .go files).

## When to Use This Skill

**MUST be invoked** before reading or modifying Go source files. Invoke this skill BEFORE launching Explore agents on charly/ code.

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM under `vm:` in `vm.yml`.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See CLAUDE.md R1–R10.
