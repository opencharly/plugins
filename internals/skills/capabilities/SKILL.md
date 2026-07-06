---
name: capabilities
description: |
  MUST be invoked before any work involving: OCI label contract, Capabilities / BoxMetadata struct, CapabilityLabelMap completeness check, LabelService structured round-trip, source-less deploy via `charly bundle from-box`, or adding a new OCI label. Developer-facing; users author via `/charly-image:layer` and `/charly-image:image`.
---

# Capabilities — the OCI-label runtime contract

Every opencharly image carries a complete snapshot of "what can this image do, what does it need, what does it provide" as `ai.opencharly.*` OCI labels. This skill documents the contract, the single Go type behind it, the completeness test that keeps it honest, and the source-less deploy path it enables.

Source of truth: `charly/capabilities.go` + `charly/labels.go`. The CLI read-side probe is `charly box labels <ref>` (whole contract sorted; `--format <key>` for one raw value with a non-zero exit when absent; `--all` for non-charly labels too) — the charly-native R8 artifact check. See also `/charly-internals:go` for the broader Go architecture and `/charly-internals:install-plan` for how this feeds the build/deploy IR.

**Boundary-law note.** The `ai.opencharly.*` label contract is a **resolved-envelope** contract, not a typed-kind one (`/charly-internals:plugin` "The kernel/plugin boundary law"): an image advertises what it provides / needs / can do as generic label DATA that any consumer reads by key — the kernel never imports a concrete kind's `spec.<Kind>` type to interpret a label. A new capability field is generic label vocabulary (Data), gated by `TestCapabilityLabelCompleteness`; it never adds a per-kind branch.

## The `Capabilities` type alias

```go
// charly/capabilities.go:29
type Capabilities = BoxMetadata
```

`Capabilities` is a **Go type alias** — not a separate struct. Every existing consumer that holds an `*BoxMetadata` (there are many) transparently participates in the capabilities contract. New code (K8s generator, `charly bundle from-box`) uses the canonical `Capabilities` name for readability. Aliasing (rather than wrapping) means there's exactly one place fields are defined: `BoxMetadata` in `charly/labels.go`.

Why this matters: adding a field anywhere in `BoxMetadata` automatically becomes part of the capabilities contract, which means it MUST have a `CapabilityLabelMap` entry. Forget the entry and CI blocks the PR.

## `CapabilityLabelMap` — field → OCI-label name

`charly/capabilities.go:35` names every label that participates in the contract. Entry grouping (identity / account / ports / security / networking / env / engine+init / distro+builder / hooks+vm / skills / data / dependency-graph / tests) mirrors the `BoxMetadata` field ordering so the map reads as a spec of the on-disk format.

Key entries:

| Field | Label const | What it stores |
|---|---|---|
| `Version` | `LabelVersion` (`ai.opencharly.version`) | The image's content-derived **`EffectiveVersion`** — its dedicated `version:` if set, else the highest layer `version:` across the chain (`charly/effective_version.go`). NOT the per-build tag; stable when no layer changed. Short-name resolution + `charly clean` retention prefer this label over the tag. Also the "is this an charly image?" presence sentinel (`ExtractMetadata` returns nil when empty). |
| `Service` | `LabelService` (`ai.opencharly.service`) | **Structured JSON array of `CapabilityService`** — not just names. 23 per-entry fields including `kind`, `events`, `auto_start`, `start_retries`, `priority`, `init`, `layer`. See "LabelService" below. |
| `Init` | `LabelInit` | Init system name (supervisord / systemd / none). |
| `InitDef` | `LabelInitDef` (`ai.opencharly.init_def`) | **`*CapabilityInitDef`** — the build-resolved runtime subset of the init: vocabulary entry: `entrypoint`, `fallback_entrypoint`, `management_tool`, `management_commands`. Makes the init system TRUE single-source: `resolveEntrypointFromMeta` (container entrypoint) and `resolveInitDefFromMeta` (in-container service-management) read this label FIRST, falling back to the legacy `wellKnownInitDefs` registry only for pre-`init_def`-label images. Because the contract travels in the label, init systems declared ONLY in the embedded vocabulary now work at runtime too. |
| `ServiceNames` | `LabelInit` | Per-init active-name list; baked alongside `LabelInit` for CLI ergonomics (e.g., `charly service status`). |
| `Description` | `LabelDescription` (`ai.opencharly.description`) | **Three-section `{candy, box, deploy}` `LabelDescriptionSet`** — the self-description baked into the image. Each `LabeledDescription` carries a `Description` string plus a `Plan []Step` list (each step is an intent keyword `run:`/`check:`/`agent-run:`/`agent-check:` + an inline Op); the deterministic `check:` steps are the acceptance checks consumed by `charly check live` / `charly check box`. See `/charly-check:check`. |
| `CheckLevel` | `LabelCheckLevel` (`ai.opencharly.check_level`) | The per-box acceptance-depth rung (`none` / `build` / `noagent` (default) / `agent`) gating how deep `charly check run <bed>` drives acceptance. |
| `Shell` | `LabelShell` | Three-section `{candy, box, deploy}` JSON shell-init manifest. Each entry carries an Origin (candy name / "box" / "deploy"), an ID for overlay keying, an optional Generic body (intrinsic init + path_append) and a per-shell ByShell map (bash/zsh/fish/sh sub-blocks). Consumed by `charly box inspect`, `charly bundle from-box`, and `MergeDeployShell` for charly.yml `shell:` overlay merging. See `/charly-image:layer` "Shell Init Surface". |
| `EnvProvide` / `MCPProvide` | `LabelEnvProvide` / `LabelMCPProvide` | Cross-container discovery: what env vars / MCP servers this image advertises to pod peers. |
| `EnvRequire` / `MCPRequire` | `LabelEnvRequire` / `LabelMCPRequire` | What this image *needs* from peers — validated at `charly config` time. |

## `TestCapabilityLabelCompleteness` — the guardrail

`charly/capabilities_test.go:TestCapabilityLabelCompleteness` runs on every `go test ./...` invocation. It uses `reflect.TypeOf(BoxMetadata{})` to enumerate every exported field and fails if any field is missing from `CapabilityLabelMap`:

```go
// charly/capabilities.go:143
func checkCapabilityLabelCompleteness() error {
    rt := reflect.TypeOf(BoxMetadata{})
    var missing []string
    for i := 0; i < rt.NumField(); i++ {
        name := rt.Field(i).Name
        if _, ok := CapabilityLabelMap[name]; !ok {
            missing = append(missing, name)
        }
    }
    // ...
}
```

This is the enforcement mechanism that keeps the OCI-label contract and the Go struct in sync. **Workflow for adding a capability:**

1. Add the field to `BoxMetadata` in `charly/labels.go` with a JSON tag.
2. Add the label const (`LabelFoo = "ai.opencharly.foo"`) next to the other label consts.
3. Add the `CapabilityLabelMap` entry: `"Foo": LabelFoo`.
4. Emit + parse the label in `writeLabels` (via `writeJSONLabel`) / `ExtractMetadata`.
5. `go test ./...` passes.

Skip step 3 and the test fails with `BoxMetadata fields without CapabilityLabelMap entry: [Foo]`.

## `LabelService` — structured per-entry service data

The services label is a full structured round-trip — not a flat list of names:

```go
// charly/labels.go (CapabilityService struct, paraphrased)
type CapabilityService struct {
    Name             string
    Scope            string            // system / user
    Enable           bool
    UsePackaged      string            // name of distro-shipped unit to reuse
    Exec             string
    Env              map[string]string
    Restart          string
    WorkingDirectory string
    User             string
    After            []string
    Before           []string
    Stdout           string
    StopTimeout      string
    Kind             string            // "program" (default) | "eventlistener"
    Events           string            // required when Kind == "eventlistener"
    AutoStart        *bool             // three-state; supervisord autostart=
    StartRetries     int
    StartSec         int
    StopSignal       string
    ExitCode         string
    Priority         int
    Init             string            // which init owns it (supervisord / systemd)
    Layer            string            // source layer name
}
```

**Why this matters**: `charly bundle from-box` (see below) reconstructs the full deploy surface from OCI labels alone. A names-only `Service` label would leave deploy-time K8s manifest generation blind to whether a process needs `start_retries: 3` or is an eventlistener. The structured label carries every supervisord directive faithfully, and the K8s Kustomize generator (see `/charly-kubernetes:kubernetes`) reads from it without touching the source repo.

## Source-less deploy: `charly bundle from-box`

`CapabilitiesFromLabels(engine, imageRef)` at `charly/capabilities.go:166` is the source-less entry point: given an engine + image ref, it runs `ExtractMetadata` (which pulls labels via `podman inspect` / `docker inspect`), returns a fully-populated `*Capabilities`, and every downstream consumer (deploy target, K8s generator, quadlet generator) reads from that struct.

```go
caps, err := CapabilitiesFromLabels("podman", "ghcr.io/opencharly/fedora-coder:latest")
// caps.Service[0].Kind == "eventlistener" works — no source repo needed
```

This is what enables the "**K8s deploy without access to charly.yml**" invariant: a Kustomize overlay can be generated from a published image alone, for dev/staging/prod clusters that never see the build repo.

## Three-layer image architecture (planned schema split)

The long-term direction (documented in `charly/capabilities.go:17-22`) is to split `BoxConfig` into three discriminated sections:

- `box.build:` — Containerfile inputs (base image, layers, distro/builder selection). Consumed only by `charly box build`.
- `box.capabilities:` — the runtime contract documented here. Emitted as OCI labels.
- `box.deploy:` — target-specific defaults (K8s storage class, container-target port defaults). Consumed by `charly bundle add`.

Today these co-exist in a single `BoxConfig`. The `Capabilities` alias is the stepping stone — once the schema split lands, `Capabilities` will point at the `capabilities:` subsection directly instead of aliasing the whole struct. The `CapabilityLabelMap` completeness test will keep the contract honest across the migration.

See `/charly-image:image` for current user-facing structure and `/charly-build:migrate` for the one-shot `charly migrate` converter that emits the new schema when the split lands.

## Adding a new OCI label — checklist

1. Add the const to `charly/labels.go` (`LabelFoo = "ai.opencharly.foo"`).
2. Add the field to `BoxMetadata` with a matching JSON tag.
3. Add the `CapabilityLabelMap` entry: `"Foo": LabelFoo`.
4. Populate it in `writeLabels` (label emission at build time, via `writeJSONLabel` for struct/list values).
5. Parse it in `ExtractMetadata` (label read-back at deploy time).
6. If the field is a struct/list, route it through `writeJSONLabel` for consistent encoding (see how `LabelService`, `LabelDescription`, `LabelVolume` do it).
7. `go test ./...` — `TestCapabilityLabelCompleteness` passes.
8. Update `/charly-internals:capabilities` (this skill) with the new entry in the key-labels table.

## See Also

- `/charly-image:image` — user-facing `candy:` image entries (with `base:`/`from:`) in `charly.yml`
- `/charly-image:layer` — user-facing `candy:` authoring, including `service:` which feeds `LabelService`
- `/charly-core:deploy` — `charly bundle add` / `from-image` / `sync` commands
- `/charly-kubernetes:kubernetes` — K8s deploy target that reads `LabelService` to generate Kustomize
- `/charly-check:check` — three-section `LabelDescription` (candy/box/deploy) — same label-contract pattern
- `/charly-build:migrate` — `charly migrate` — emits the schema that populates these labels
- `/charly-internals:go` — Go architecture overview, `LoadUnified`, `parseCandyYAML`
- `/charly-internals:install-plan` — internal IR shared across build and deploy pipelines
