---
name: egress
description: |
  CUE EGRESS validation — validating (and, where it adds value, generating) the
  config files charly WRITES to a system BEFORE the bytes hit disk. MUST be
  invoked before working on charly/egress.go, the vendored schemas under
  candy/plugin-egress/egress-schemas/vendor/, the ValidateEgress / registerVendoredEgressKind path,
  the offline `task cue:vendor` pipeline, or adding an egress schema for any
  written artifact (cloud-init, k8s manifests, traefik routes, runtime config,
  install ledger, systemd/quadlet units, ssh_config, libvirt XML).
---

# egress — validating the config files charly writes

## Overview — ingress vs egress

> **M16 — egress is a PLUGIN.** The validation logic + the CUE schemas now live in the
> COMPILED-IN `candy/plugin-egress` (serving `verb:egress` / `OpValidate`); the egress CUE files
> moved to `candy/plugin-egress/egress-schemas/` (+ `vendor/cloud_config.cue`). `charly/egress.go`
> is now a THIN SHIM: `ValidateEgress`/`ValidateEgressValue`/`validateTextEgress`/`ValidateXMLEgress`
> keep their signatures but resolve `verb:egress` + `Invoke(OpValidate, {kind,label,mode,data})`
> (plain host→plugin dispatch). Every caller + the `vmshared.ValidateEgress` hook are unchanged. The
> plugin holds its schemas INTERNALLY (compiled in its own cue context — the package-less defs
> concatenated, the vendored `cloud_config` as its own instance) and serves only a trivial Describe
> schema, so the vendored package+import file never joins the single-blob Describe concat. The
> validation SEMANTICS below (the kinds, the two-layer model, the constraints) are unchanged — only
> the code's HOME moved. Compiled-in: the build/deploy hot paths call it many times; an in-proc
> inprocProvider pays only a JSON envelope over a CUE-unify that dominates.

charly's CUE work has two halves:

- **Ingress** (`charly/cue_schema.go`): validates the INPUT config a user authors
  (`charly.yml` / box / candy / vm / k8s / pod) against `sdk/schema/*.cue`, AND is
  the single source for the Go param structs that config decodes into — the
  `@go()`-annotated `sdk/schema/*.cue` GENERATE the `sdk/spec` param structs via
  `task cue:gen` (`cue exp gengotypes`, run in the sdk repo; the superproject task
  chains it), kept honest by the reproducibility + parity tests. Owned by `/charly-build:validate`; the schema-change codegen
  recipe is `/charly-internals:go` "Updating Go code when an ingress CUE schema
  changes".
- **Egress** (`charly/egress.go`, this skill): validates the OUTPUT config charly
  WRITES onto a system — the seed ISO's cloud-init, Kustomize manifests, quadlet
  and systemd units, the ssh_config fragment, the install ledger, libvirt domain
  XML, … — BEFORE the bytes are written. Ingress proves the input; egress proves
  the output. A malformed artifact fails loudly in charly with a precise CUE
  error instead of silently on the target. Egress is **validation-only**: it
  shares no codegen path with ingress — `ValidateEgress` ingests already-rendered
  bytes and is unchanged by the ingress single-source-schema work.

## Two-layer model (what CUE can and cannot do)

CUE operates on structured data (YAML/JSON) and strings — it has no parser for
Dockerfile / systemd-INI / ssh_config. So egress validation is layered:

1. **Structured YAML/JSON outputs** (cloud-init, k8s, traefik, runtime config,
   ledger) validate DIRECTLY — ingest the rendered bytes, unify with the schema.
2. **Non-data text outputs** (quadlet, systemd units, shell rc, ssh_config,
   Containerfile) validate via their **structured pre-image** (the Go model just
   before rendering) plus an optional `text`-encoding constraint check on the
   rendered string (no unresolved `${VAR}`, required sections present).
3. **XML** (libvirt) validates via CUE's experimental `xml+koala` decode.

## The validator API — the `charly/egress.go` SHIM (M16)

These four public functions keep their signatures; each resolves `verb:egress` + `Invoke(OpValidate,
{kind,label,mode,data})` and turns the plugin's `{error}` verdict into a Go error. The plugin's
`provider.validate` runs the actual unify (the SAME CUE code that used to live here), keyed on `mode`:

| Function | mode | Purpose |
|----------|------|---------|
| `ValidateEgress(kind, label, data []byte) error` | `bytes` | Ingest serialized YAML/JSON bytes, unify with the egress kind's schema, `Validate(cue.Concrete(true))`. JSON is a YAML subset, so one ingest path covers both. |
| `ValidateEgressValue(kind, label, v any) error` | `bytes` | Marshal the in-memory Go value (a manifest `map[string]any`, a record struct) to JSON, validate as bytes — faithful for the data values egress gates (k8s manifests, ledger records). |
| `validateTextEgress(label, text string) error` | `text` | Validate a rendered NON-DATA text artifact (Containerfile, service unit) by unifying it as a CUE string with `#RenderedText` (rejects the Go text/template `<no value>` nil-field marker). No concreteness. |
| `ValidateXMLEgress(kind, label, xml string) error` | `xml` | Validate a rendered XML artifact (libvirt domain) via the EXPERIMENTAL `cuelang.org/go/encoding/xml/koala` decode unified with a koala-shaped def, `Validate(cue.Concrete(true))`. **Best-effort**: a koala *decode* error → pass (defers to the authoritative downstream gate); only a schema violation on a decoded document hard-fails. |

Inside the plugin, the package-less defs are concatenated + `LookupPath`'d via `kindDefPaths`, and the
vendored `cloud_config` is `CompileBytes`-compiled as its own instance — there is no longer a
`registerVendoredEgressKind` / `egressDef` / `cueKindDef` fallback in charly core.

A failed `ValidateEgress` returns the CUE error (`errors.Details`) and the caller
aborts the write — the gate is always-on (no opt-in flag), consistent with
charly's "CUE owns validation, hard-error" rule.

## Schema sources — the separate-compile constraint (load-bearing)

The egress schemas live in `candy/plugin-egress/egress-schemas/` and are compiled in the plugin's
OWN `cuecontext.New()` at `newProvider()` (M16). Two sources, exactly mirroring the former in-core
split:

- **PACKAGE-LESS egress schemas** (`egress-schemas/egress_*.cue` → `#RenderedText`, `#K8sObject`,
  `#DeployRecord`, `#CloudInitMeta`, …) are import-free, so the plugin **string-concatenates them
  into ONE `CompileString`** (one shared scope) and `LookupPath`s each def via the `kindDefPaths` map.
- **VENDORED schemas** (`egress-schemas/vendor/cloud_config.cue`, an upstream JSON Schema run through
  `cue import jsonschema:`) carry a `package` clause + CUE-stdlib `import (...)`, so they **cannot**
  join that concatenated blob. The plugin compiles `cloud_config.cue` as its OWN instance via
  `CompileBytes` (the CUE-stdlib imports resolve in the bare context with no module loader) and stores
  `defs["cloud_config"]` separately.
- **The schemas are held INTERNALLY, NOT served over Describe.** `Describe` ships only a trivial
  `#EgressInput` (`candy/plugin-egress/schema/`) to satisfy the host plugin-schema gate — so the
  vendored `package`+`import` file never has to join the SDK's single-blob `BuildCapabilities` /
  `ConcatSchema` / `CompileString` Describe contract (the move that would otherwise break).

## The offline vendoring pipeline (`task cue:vendor`)

Vendoring keeps charly a hermetic single binary — schemas are converted to plain
`.cue` at DEV time and embedded; nothing is fetched at runtime. Requires the `cue`
CLI (the `/charly-tools:cue` candy):

1. pin the upstream source under `candy/plugin-egress/egress-schemas/vendor/sources/`;
2. `cue import -f -p schema -l '#<Def>:' -o candy/plugin-egress/egress-schemas/vendor/<name>.cue jsonschema: <source>`;
3. (curated registry modules) `cue mod get cue.dev/x/...` then extract the needed defs;
4. the generated `.cue` is committed pristine, so a reproducibility test can match `cue import` output.

`candy/plugin-egress/egress-schemas/vendor/README.md` records the exact regen commands + pinned versions.

## What's validated today

| Artifact | Writer | Kind | Schema |
|----------|--------|------|--------|
| cloud-init **user-data** | `RenderCloudInit` (`cloud_init_render.go`) | `cloud_config` | vendored Canonical cloud-config (`egress-schemas/vendor/cloud_config.cue`, `#CloudConfig`) |
| cloud-init **meta-data** | `RenderCloudInit` | `cloud_init_meta` | `egress-schemas/egress_cloud_init.cue` `#CloudInitMeta` |
| cloud-init **network-config** | `RenderCloudInit` | `cloud_init_net` | `egress-schemas/egress_cloud_init.cue` `#NetworkConfigV2` |
| **k8s manifests** (Deployment/StatefulSet/DaemonSet/Job/CronJob/Pod/Service/PVC/Ingress) | `GenerateK8sKustomize` → `writeK8sYAML` (`k8s_generate.go`) | `k8s_object` | `egress-schemas/egress_k8s.cue` `#K8sObject` envelope (validates structure — the egress failure mode for machine-generated manifests; deep per-field types are an ingress concern) |
| **k8s Kustomization** (base + overlay) | `GenerateK8sKustomize` → `writeK8sYAML` | `kustomization` | `egress-schemas/egress_k8s.cue` `#Kustomization` |
| **install-ledger deploy record** | `WriteDeployRecord` / `WriteDeployRecordVia` (`install_ledger.go`) | `deploy_record` | `egress-schemas/egress_ledger.cue` `#DeployRecord` (requires `deploy_id`/`target`/`deployed_at`; `image` optional — candy-only deploys leave it empty) |
| **install-ledger candy record** | `WriteCandyRecord` / `AddCandyDeploymentVia` | `candy_record` | `egress-schemas/egress_ledger.cue` `#CandyRecord` (requires `candy`/`deployed_at`; steps/reverse_ops open) |
| **traefik dynamic config** (`.build/<box>/traefik-routes.yml`) | `generateTraefikRoutes` (`generate.go`) | `traefik_routes` | `egress-schemas/egress_traefik.cue` `#TraefikRoutes` (hand-built YAML — non-empty Host rule / service / backend url; null routers/services when no route candies) |
| **Containerfile** (`.build/<box>/Containerfile`) | `writeContainerfile` (`generate.go`) | `rendered_text` | `egress-schemas/egress_text.cue` `#RenderedText` (rejects the `<no value>` template-failure marker) |
| **systemd/supervisord service units** | `RenderService` (`service_render.go`) | `rendered_text` | `egress-schemas/egress_text.cue` `#RenderedText` (same template-failure gate) |
| **libvirt domain XML** | `RenderDomainXML` (`libvirt_yaml_bridge.go`) | `libvirt_domain_xml` | `egress-schemas/egress_libvirt_xml.cue` `#LibvirtDomainXML` (koala-shaped structural envelope — non-empty `$type`/`name.$$`/`memory.$$`; best-effort, libvirt `DomainDefineXML` is the authoritative gate) |

## Deliberately NOT egress-validated

The gate earns its keep on output that is HAND-ASSEMBLED with real invariants
(traefik routes, ledger records) or that incorporates external/variable data
(cloud-init Extra, k8s capabilities from labels). It is **intentionally not added**
where the writer is a straight `yaml.Marshal(typedStruct)` of charly's own struct
with no transformation — the output cannot malform by construction, so a schema
would be validation theater:

- **runtime config** `~/.config/charly/config.yml` (`SaveRuntimeConfig` — pure `yaml.Marshal(*RuntimeConfig)`).
- **deploy-state** `~/.config/charly/charly.yml` (`SaveBundleConfig`) — additionally, project config is already CUE-validated on LOAD (ingress).

## Caveats

- **`matchN` disables closedness.** A schema imported from a Draft-04 JSON Schema
  (cloud-config) uses `matchN` (anyOf), which means CUE does NOT reject unknown
  keys — it catches TYPE/structure violations, not typos. Acceptable for egress
  (validating output charly itself generated). charly's hand-authored egress
  schemas stay `close({...})`.
- **CUE reorders keys.** Any generation path (`cueyaml.Encode`) emits keys sorted —
  output is SEMANTICALLY equal to a hand-marshal, never byte-identical. Round-trip
  tests must parse-and-compare.

## Adding a new egress schema (recipe)

The schemas + validation now live in `candy/plugin-egress` (M16):

1. Add the schema CUE under `candy/plugin-egress/egress-schemas/` — a package-less file (it joins
   the plugin's concatenated def set) OR, for an upstream JSON-Schema needing a `package`+imports,
   `candy/plugin-egress/egress-schemas/vendor/` (compiled as its own instance in `newProvider`).
2. Register the kind→def-path in the plugin's `kindDefPaths` map (package-less) or add a
   `defs[kind] = …` CompileBytes branch (vendored), in `candy/plugin-egress/main.go`.
3. Call the matching in-core shim (`ValidateEgress` / `ValidateEgressValue` / `validateTextEgress` /
   `ValidateXMLEgress`) at the writer's seam, BEFORE the `os.WriteFile` / `PutFile`, returning its
   error — the shim resolves `verb:egress` + `Invoke(OpValidate)`.
4. Add corpus + teeth tests in `candy/plugin-egress/egress_test.go` (a good artifact passes, a
   malformed one is rejected) — mirror `TestEgressValidate`.

## Cross-References

- `/charly-tools:cue` — the `cue` CLI candy that drives the vendoring pipeline.
- `/charly-build:validate` — the ingress side (`charly box validate`).
- `/charly-internals:cloud-init-renderer` — the first egress consumer (`RenderCloudInit`).
- `/charly-internals:install-plan` + `/charly-internals:local-infra` — the DeployTargets/writers whose seams the egress gate plugs into.
- `/charly-internals:go` — the Go source map (`egress.go`, `cue_schema.go`).

## When to Use This Skill

Invoke before working on `candy/plugin-egress` (the validation logic + the egress CUE schemas
under `candy/plugin-egress/egress-schemas/` incl. `vendor/cloud_config.cue`), the `charly/egress.go`
in-core SHIM, the `ValidateEgress` path,
the `task cue:vendor` pipeline, or adding/validating any config file charly writes
to a system.
