---
name: cue
description: |
  The CUE data-validation / configuration CLI (cue), pinned to v0.16.1.
  Use when working with the cue candy, installing the cue binary into a box or
  onto a target:local dev host, or running the offline schema-vendoring pipeline
  that feeds charly's egress validation.
---

# cue — CUE CLI (data validation + schema vendoring)

## Candy Properties

| Property | Value |
|----------|-------|
| Candy | `candy/cue` |
| Binary | `/usr/local/bin/cue` |
| Version | pinned `v0.16.1` (matches charly's embedded `cuelang.org/go` library) |
| Install | `download:` the cue-lang GitHub release tarball, extract `cue` (cross-distro, no `package:`) |
| Status | testing |

## What it installs

A single static Go binary, `cue`, from the pinned cue-lang GitHub release
(`cue_v0.16.1_linux_${ARCH}.tar.gz`). No distro packages — the `download:` verb
fetches and extracts the one binary, so the candy is distro-agnostic.

## Why it exists — a DEV-TIME tool, not a runtime dependency

charly's **runtime never shells out to `cue`** — every build/deploy/check path
validates through the **embedded `cuelang.org/go` library** (the `cueSchemaCtx`
in `charly/cue_schema.go`, and the egress validator in the compiled-in
`candy/plugin-egress` — M16 — fronted by the `charly/egress.go` shim). The `cue`
CLI is here for the **developer/agent workflow**:

- running the offline schema-vendoring pipeline (`cue import jsonschema:`,
  `cue mod get`) that produces the `.cue` files charly embeds — see
  `/charly-internals:egress`;
- authoring + spot-checking schemas (`cue vet`, `cue export`) in a charly dev/coder box.

Pin v0.16.1 so the CLI that vendors a schema is the SAME CUE version the embedded
library compiles it with — a newer CLI could emit constructs the pinned library
rejects.

## Verification (ADE)

The candy's `plan:` ships deterministic `check:` steps: the binary lands at
`/usr/local/bin/cue`, `cue version` reports the pinned `v0.16.1`, and a real
`cue export` of a computed field (`y: x*2` → `42`) proves the binary actually
evaluates CUE — a non-functional binary fails the check.

## Install on a dev host

```bash
charly bundle add cue cue --target local   # installs /usr/local/bin/cue on this host
```

…then the `task cue:vendor` pipeline (see `/charly-internals:egress`) can run.

## Cross-References

- `/charly-internals:egress` — the egress-validation subsystem the cue CLI feeds (the vendoring pipeline, `candy/plugin-egress/egress-schemas/vendor/`).
- `/charly-build:validate` — `charly box validate` (the ingress side; uses the embedded library, not this CLI).
- `/charly-image:layer` — the `download:` verb the candy uses.

## When to Use This Skill

Invoke when working with the `cue` candy, installing the cue CLI into a box or
onto a target:local host, or before running the schema-vendoring pipeline.
