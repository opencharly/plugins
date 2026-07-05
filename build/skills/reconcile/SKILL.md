---
name: reconcile
description: |
  Use when @github layer/namespace pins drift across repos and the resolver emits
  "referenced at multiple versions" warnings — `charly box reconcile` aligns every
  pin of a repo to one version (clearing the warnings). Invoked as
  `charly box reconcile`.
---

# charly box reconcile — align cross-repo `@github` version pins

Invoked as `charly box reconcile`. See `/charly-image:image` for the family overview.

## Overview

The layer resolver compares each layer's PER-ENTITY `version:` (read after fetch),
not the repo git tag — so a repo re-tag of an UNCHANGED layer does NOT warn. When
a layer DOES resolve to two different per-entity versions (a family pinned to a
genuinely newer layer than the shared infra it composes), it **warns once and uses
the newest** (see `/charly-internals:go` "Remote-layer resolver", `/charly-build:validate`).
The git `:vTAG` is only the FETCH coordinate. `charly box reconcile` aligns the
on-disk git-tag pins — for each distinct repo referenced by the project's
versioned YAML, it rewrites EVERY pin of that repo to ONE target tag, so every
reference fetches one commit per repo and the next `charly box generate` emits
**zero** version warnings. Edits are comment-preserving (yaml.v3 node API) and idempotent.

The **zero-warnings R10 gate** (CLAUDE.md R1) makes this load-bearing: a change
that introduces a version mismatch is not landable until `charly box reconcile`
clears the warning.

## Quick Reference

| Action | Command | Description |
|---|---|---|
| Preview rewrites | `charly box reconcile --dry-run` | Print every pin it would change; touch nothing |
| Align to newest referenced | `charly box reconcile` | Rewrite each repo's pins to the newest version ALREADY referenced (offline) |
| Align to newest remote tag | `charly box reconcile --remote` | Query `git ls-remote --tags` per repo and bump to the newest tag |

```bash
charly box reconcile --dry-run      # see the plan
charly box reconcile                # align to newest referenced (no network)
charly -C box/cachyos box reconcile   # reconcile a submodule's pins
```

## What it does

1. **Scan** every `@github.com/owner/repo[/path]:vTAG` ref in the project's
   versioned YAML files (`charly.yml` + discovered `box/<name>/charly.yml` /
   `candy/<name>/charly.yml`, plus any flat-imported legacy per-kind files —
   `charly.yml` / `check.yml` / `local.yml` / `pod.yml` / `k8s.yml` / `vm.yml` /
   `charly.yml`). Refs appear in `import:` namespaces, image `base:` / `builder:` /
   `candy:`, and `kind:local` `candy:` lists.
2. **Target** per repo: the newest version ALREADY referenced (default —
   `compareSemver`, orders CalVer correctly, no network) or, with `--remote`, the
   newest tag on the remote (`GitLatestTag`).
3. **Rewrite** every pin of that repo whose version differs from the target,
   preserving comments and key order. Unpinned refs and single-version repos are
   left untouched. Idempotent: a second run rewrites nothing.

## Scope — one project per invocation

`charly box reconcile` operates on the CURRENT project (cwd; honors the top-level
`-C` / `--dir` / `CHARLY_PROJECT_DIR`). For a multi-repo tree (the main repo + its
`box/<distro>` submodules), run it per repo, or per submodule via `-C
image/<name>`. This pairs with the cross-repo landing order in
`/charly-internals:git-workflow` B6: land + tag the producer FIRST, then
`charly box reconcile` repoints the consumer to the producer's fresh tag before the
consumer's authoritative R10.

## Implementation

`charly/reconcile.go` — `ImageReconcileCmd` (wired under `charly box` in `charly/image.go`).
Reuses `ParseRemoteRef` / `IsRemoteCandyRef` / `StripVersion` (`charly/refs.go`),
`compareSemver` / `GitLatestTag` / `RepoGitURL` (`charly/refs_git.go`), and the
comment-preserving load/`yaml.Marshal` pattern from `sdk/kit/yaml.go`. Covered
by `charly/reconcile_test.go` (newest-referenced alignment, comment preservation,
idempotency, single-version-untouched, no-pins no-op).

## Cross-References

- `/charly-internals:go` "Remote-layer resolver" — the warn-and-newest-wins resolver this aligns to.
- `/charly-build:validate` — surfaces the multi-version warning reconcile clears.
- `/charly-internals:git-workflow` — cross-repo (B6) producer→consumer landing that calls reconcile.
- `/charly-build:migrate` — per-push CalVer tags that reconcile pins point at.
- `/charly-image:image` — `import:` / namespace authoring + the family overview.

## When to Use This Skill

Invoke when the resolver warns that a layer is referenced at multiple versions,
when aligning a consumer's pins to a freshly-tagged producer, or whenever you need
the project's `@github` pins consistent for a zero-warnings R10.
