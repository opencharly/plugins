---
name: local-spec
description: |
  MUST be invoked before any work involving: authoring `kind: local` templates, `local.yml` files, inline `kind: local` template nodes in `charly.yml`, or the merge semantics between a `kind: local` template and the deploy that deploys it.
---

# kind: local — Authoring Reference

## Overview

`kind: local` declares a reusable candy-stack template that gets applied to a Linux filesystem (deployed by a `local:` deploy whose `from:` field selects this template). Unlike `kind: pod` / `kind: vm` / `kind: k8s` which wrap an image, a `kind: local` is defined entirely by its `layers` + `install_opts` + `env` — there's no OCI artifact backing it. The convention file is `local.yml`; templates may also be authored inline in `charly.yml` as top-level name-first nodes (`<name>: { local: {…} }`).

Legacy `kind: host` projects migrate via `charly migrate`.

## Schema

```yaml
# Name-first: the entity flattens to a top-level <name>: key whose `local:`
# block holds the FULL body — scalars, collections inline, and the plan as an
# ordered `plan:` list of steps.
dev-workstation:
  local:
    description: Standard developer workstation profile   # optional — plain string
    candy:                       # required (use [] for a placeholder; see below)
      - ripgrep
      - direnv
      - uv
    install_opts:                # optional — defaults merged 3-tier (CLI > deploy > template)
      with_service: false
      allow_repo_changes: true
    env:                         # optional — a map
      EDITOR: vim
    plan:
      - check: ripgrep is installed after deploy   # one intent keyword + inline Op
        command: rg --version
        context: [deploy]
```

## Inline form in charly.yml

```yaml
version: 2026.144.1443

dev-workstation:
  local:
    description: Dev workstation
    candy: [ripgrep, direnv]
    install_opts: {with_service: false, allow_repo_changes: true}
    env: {EDITOR: vim}

ci-runner:
  local:
    description: CI runner profile
    candy: [ripgrep, pixi, cargo-toolchain]
    install_opts: {with_service: true, allow_root_tasks: true}

charly-cachyos-app:
  local:
    description: CachyOS DX (placeholder)
    # Empty placeholder — `candy: []` is a load-time WARNING (allowed
    # for staged template name reservation); a missing `candy:` field
    # is a hard error.
    candy: []
    install_opts: {}
```

## Field reference

| Field | Required | Description |
|---|---|---|
| `layers` | Yes | Ordered candy stack. `[]` permitted as a placeholder (warning, not error). |
| `install_opts` | No | Default install gates. Deployment overrides merge on top. |
| `env` | No | Shell-profile env vars as a `{KEY: value}` map. Deployment env wins on key collision. |
| `description` | No | Plain string — the profile's purpose; first line = the summary. |
| `plan` | No | An ordered list of steps inline in the kind value — each one intent keyword: `run:` (state-change) / `check:` (deterministic probe) / `agent-run:` / `agent-check:` / `include:` — carrying prose plus, for `run:`/`check:`, an inline Op (verb + matchers + `context:`), and an optional `id:`. Deploy-scope steps carry `context: [deploy]`. Merged with the deploy's plan. |

There is **no** `status:` or `info:` field; `description` is the human-facing summary string.

## What the deploy does NOT do

A `kind: local` deploy emits **zero** container-image fetch / build
steps. The deploy applies host packages + configs only. There is no
`image:` field; declaring one in legacy YAML hard-errors at
`charly box validate` time with a pointer to `charly migrate`.

Test-bed image preflight is the **check entry point's** job, not the
deploy's. When `charly check run --on-host <name>` resolves to a host
target, the runner walks the bed's plan steps, collects every distinct
step `pod:` value plus the bed's target image, and ensures each
image is present in local podman storage (LocalImageExists →
`charly box pull` → fall back to `charly box build` for short names that
resolve via `cfg.Images`). Operators who never run `charly check run`
never pay the image-fetch cost. See `/charly-check:check` "Image
preflight" and `charly/check_image_preflight.go`.

This invariant — "deploy fetches NOTHING speculative" — is codified
as a project-rulebook Key Rule (`AGENTS.md` / `CLAUDE.md`) and enforced at the type level: the
`LocalSpec` Go struct has no `Images` field, so the surface is
unreachable from any new code. Migration: `charly migrate`
(idempotent; rewrites legacy `image:` blocks under `local.<name>`
to a dated comment fence).

## Merge semantics — `kind: local` template + a deploy

When a `local:` deploy carries `from: <template-name>`:

| Field | Template provides | Deployment overrides | CLI overrides | Effective value |
|---|---|---|---|---|
| `layers` | base list | — | — | `template.Layers` |
| `add_layers` | — | extra list | `--add-candy` | `deployment.AddCandies ++ CLI.AddCandy` |
| effective layer order | — | — | — | `template.Layers ++ deployment.AddCandies ++ CLI.AddCandy` |
| `install_opts.*` (bool) | default | wins over template | wins over both | CLI > deployment > template |
| `install_opts.builder_image` | default `""` | wins | wins over both | CLI > deployment > template |
| `env` | base list | extends + overrides on key | — | template.Env merged with deployment.Env (deployment-wins on collision) |
| `plan` | base plan | extends list | — | `template.Plan ++ deployment.Plan` |

The `InstallOptsConfig.ApplyTo` method is fill-empty — calling it on the deployment's opts first, then the template's, gives the priority chain automatically.

## Empty `candy: []` is a placeholder

A template with `candy: []` is permitted as a stub for staged name reservation:

```yaml
charly-cachyos-app:
  local:
    description: CachyOS DX (placeholder)
    candy: []
    install_opts: {}
```

`charly box validate` emits a WARNING but does not error. A missing `candy:` field entirely IS an error — its presence is the signal that the author intended a template.

## Cross-References

- `/charly-local:local-deploy` — the `target: local` deployment surface that consumes this template.
- `/charly-internals:local-infra` — Go file map (`local_spec.go`, `LocalSpec` struct, `findLocalSpec` lookup).
- `/charly-image:layer` — candy authoring (the building blocks composed by templates).
- `/charly-build:migrate` — `charly migrate` migrates legacy `kind: host`/`host.yml` projects up to the node-form schema (every entity name-first inline in `charly.yml`). The `charly-cachyos` deploy applies the suffixed `charly-cachyos-app` `kind: local` template — within one document top-level names are globally unique, so the deploy keeps the user-facing name and the template it deploys is suffixed (see "Globally-unique names within one document" below).

## Globally-unique names within one document

Every entity flattens to a top-level `<name>:` key, so within one document (the project-root `charly.yml`) top-level names must be **globally unique** — a deploy and the `kind: local` template it deploys cannot share a name (they would collide on one YAML key). The convention: keep the user-facing deploy name and **suffix the template it deploys**. The canonical example is `charly-cachyos` — the `charly-cachyos` deploy (`local: { from: charly-cachyos-app, host: local }`) deploys the `charly-cachyos-app` `kind: local` template; `charly update charly-cachyos` resolves to the deploy, which references the template via its `from: charly-cachyos-app` field. Cross-kind reuse of the SAME name across SEPARATE discovered files (a `candy/redis` + a `box/redis`) remains permitted. See the project rulebook "a single document's top-level node names are GLOBALLY UNIQUE".

## When to Use This Skill

**MUST be invoked** when the task involves authoring or editing `kind: local` templates, `local.yml` files, inline `kind: local` template nodes in `charly.yml`, or the merge between a template and the deploy that deploys it. Invoke this skill BEFORE reading Go source or launching Explore agents.
