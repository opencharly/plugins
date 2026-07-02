---
name: migrate
description: |
  MUST be invoked before any work involving: the `charly migrate` command (the single idempotent migration that brings any opencharly config up to the latest schema CalVer), the CalVer schema-version stamp (`version: YYYY.DDD.HHMM`), the CUE-anchored HEAD/floor (`charly/schema/version.cue` → `#SchemaVersion`/`#SchemaFloor`), the declarative migration table (`charly/migrations.cue`, applied by the core op-walker in `charly/migrate_engine.go`), the `LatestSchemaVersion()` load-time gate, or adding a new schema cutover as a migration-table entry.
---

# charly migrate — single-command schema migration

`charly migrate` is **one idempotent command** that brings any opencharly config — as far back as the supported schema floor — up to the **latest schema CalVer**, and only to the latest. There are no sub-verbs to choose between: `charly migrate` always applies every migration-table step newer than the config, up to HEAD.

```bash
charly migrate            # migrate every reachable config to the latest schema CalVer
charly migrate --dry-run  # print every change migrate would make; touch nothing
```

The project directory is the current working directory; use the top-level `-C` / `--dir` / `CHARLY_PROJECT_DIR` global to point elsewhere (`main()` chdir's before dispatch).

## CalVer schema versioning

The YAML schema version is a **CalVer string** — `version: YYYY.DDD.HHMM`, the same fixed-width scheme as image tags (e.g. a HEAD like `version: 2026.174.1100`). It is CANONICAL fixed-width: a 4-digit year, a 3-digit zero-padded day-of-year, and a 4-digit zero-padded HHMM, so a plain alphanumeric sort of CalVer strings is chronological. `ParseCalVer` is EXTREMELY STRICT — it accepts ONLY that exact form (no `version: 4`, no non-padded `2026.45.830`); a non-canonical value is "not a CalVer", which the load gate treats as older-than-HEAD so it flows into `charly migrate`. `charly migrate` re-stamps every versioned file it brings forward to the canonical HEAD (`universalStamp`); a value that predates the supported floor — or is not a CalVer at all — is unmigratable and refused untouched (see "How it runs"). Every versioned file carries the stamp:

- every project `charly.yml` (splitting into per-kind `vm.yml` / `local.yml` / … siblings is an optional `import:` convenience a project MAY use — never the default; see `/charly-image:image`)
- the per-host `~/.config/charly/charly.yml`

The parsed `CalVer` type, `ParseCalVer(string) (CalVer, bool)`, `CalVer.Less`, and `MustCalVer` live in **`charly/plugin/kit`**. **CUE owns the HEAD and floor:** `charly/schema/version.cue` defines `#SchemaVersion` (the HEAD CalVer every file is stamped to) and `#SchemaFloor` (the oldest version migratable FROM). `task cue:gen` emits `charly/spec/version_gen.go` with the `SchemaVersion` / `SchemaFloor` string consts; `kit.LatestSchemaVersion()` and `kit.SchemaFloor()` parse them. There is NO hand-maintained Go HEAD literal — the load-time gate requires `kit.LatestSchemaVersion()`, and `charly migrate` refuses anything below `kit.SchemaFloor()`.

### Per-push release git tags (decoupled from `version:`)

Every push of an charly-project repo (one with an `charly.yml`) carries a **fresh** annotated release git tag `v<YYYY.DDD.HHMM>` computed from the current UTC push time — ONE per push, so a repo accumulates MULTIPLE `v…` tags over time. This is **decoupled** from the `charly.yml` `version:` field: `version:` is the SCHEMA version (bumped only when a cutover raises `#SchemaVersion`), whereas the tag marks the push moment. Tag EVERY push — including one at an unchanged `version:` (a content change, submodule extraction, image drop). Tags are **immutable**: only ever ADD new ones, never move or force-push an existing tag (so the load-time gate never sees a "newer than supported" CalVer from a re-tag). Every component is fixed-width zero-padded — 4-digit year, 3-digit day-of-year, 4-digit HHMM (`v2026.064.1937`, `v2026.142.1640`) — so tags sort chronologically under a plain alphanumeric sort; compute with `v$(date -u +%Y.%j.%H%M)` (`%j` and `%H%M` are already zero-padded). Each repo (the main repo and every `box/<distro>` submodule) is tagged independently at its own push time; push submodule(s) first, then the superproject, then the tag on the pushed HEAD. Repos without an `charly.yml` (`plugins`, `pkg/arch`) are out of scope. See CLAUDE.md "Post-Execution Policies".

## The migration table (declarative data)

The migration steps are **declarative DATA, not code**: an ordered list embedded from **`charly/migrations.cue`**, validated at process start against the `#Migration` schema (`charly/schema/migration.cue`). Each step is stamped with the CalVer of the date it landed and listed **chronologically** — the order the cutovers were authored in, which is the only correct replay order for an arbitrarily-old config. `charly migrate` applies every step whose version is newer than the config's stamp; each step is idempotent, so applying the whole set is safe (an already-current file is a no-op).

A step is a small record:

```cue
{version: "YYYY.DDD.HHMM", name: "<slug>", touches_host?: bool, ops?: [...#Op] | apply?: "<hook>"}
```

`touches_host: true` flags a step that mutates per-host state (`~/.config/charly`, quadlets, `.secrets`) — those steps are skipped by remote-cache auto-migration (see below). A step carries EITHER an `ops:` list OR a single `apply:` hook, never both.

**The op vocabulary — each op is DATA, zero Go.** Four generic key transforms cover the common cutovers, all applied by ONE comment-preserving yaml.v3 interpreter (the op-walker in `charly/migrate_engine.go`):

| Op | Shape | Effect |
|---|---|---|
| `rename_key` | `{from, to, scope, under_kind?}` | rename a mapping key `from` → `to` |
| `delete_key` | `{key, scope, under_kind?}` | drop a mapping key |
| `remap_scalar` | `{key, from, to, under_kind?}` | rewrite a scalar VALUE `from` → `to` at `key` |
| `move_key` | `{key, from_parent, to_parent, under_kind?}` | relocate a key between parent mappings |

`scope` is `root` (top-level keys only) or `any` (every depth); `under_kind` further scopes an op to entities of a named kind (e.g. only `vm:` nodes). None of the four ops needs a line of new Go — the walker interprets the data.

**The `apply:` hook — the deliberate, visible EXCEPTION.** A structural reshape the four ops can't express (splitting one node into siblings, folding a list into a map) sets `apply: "<hook>"` naming a Go function registered in the core `goHooks` map. This is the ONLY path that runs bespoke Go for a migration, and it is intentionally conspicuous: a table entry carrying `apply:` is the signal that this step needed real code.

**CUE has NO transformation capability.** CUE is monotone unification — it can validate, default, require, and close, and nothing more; it CANNOT rewrite a config. So CUE owns exactly two things here: the version pins (`#SchemaVersion` / `#SchemaFloor`) and the SHAPE of the declarative table (`#Migration` validates every entry at startup). Every actual transform is Go — the generic op-walker, or an `apply:` hook. Do not expect CUE to migrate anything.

**The table currently ships EMPTY, reset to a clean baseline.** The floor is set at the reset version, so any config predating it is unmigratable — the accepted clean-slate consequence. The engine, the op vocabulary, and the floor gate are all live; the first future cutover appends the first entry.

## How it runs

`runMigrations` (`charly/migrate.go`, driving the engine in `charly/migrate_engine.go`) is **floor-gated**, comparing the config's `version:` stamp against `kit.SchemaFloor()` and `kit.LatestSchemaVersion()`:

- **at HEAD** → no-op; prints `nothing to migrate (already at schema <HEAD>)`.
- **below the floor, or not a CalVer at all** → **unmigratable**: refused with an actionable error (`predates the supported floor … re-author against the current schema`) and **NO filesystem change**. Configs from before the baseline reset fall here.
- **in `[floor, HEAD)`** → apply every migration-table step newer than the stamp (in order, via the op-walker / `apply:` hooks), then re-stamp every versioned file to HEAD (`universalStamp`).

Per-step backups follow the established `<file>.bak.<unix-ts>` convention.

### Remote-cache auto-migration (project-only)

`charly/refs.go` auto-runs `RunProjectMigrations` on a freshly-cloned remote-repo cache so external repos pull through at the latest schema. It skips every `touches_host` step and leaves the host-deploy path empty, so a remote fetch **never mutates the user's per-host state** — even the final re-stamp touches only the cache's project files. A remote whose config predates the floor **fails the fetch** with the same predates-floor error (an old remote is unmigratable — the accepted clean-slate consequence).

## Load-time gate

The load-time gate `gateSchemaVersion` (`charly/unified.go`) is unchanged: `LoadUnified` parses the merged `version:` and rejects anything below HEAD (or absent, or non-CalVer):

```
charly.yml: schema 2026.174.1100 is required (found "4"). Run: charly migrate
```

A non-CalVer value (a legacy integer, empty, or garbage) parses as "older than every real CalVer", so a stale config trips the gate with a uniform `Run: charly migrate` hint — the forward-compat trigger that makes a future migration fire. Whether that migrate then SUCCEEDS depends on the floor: a config in `[floor, HEAD)` migrates; one below the floor is refused (see "How it runs"). Residual-key checks (e.g. `kind: deployment`, `target: host`, `secret_backend: kdbx`) remain as defense-in-depth, but every remediation hint points uniformly at bare `charly migrate`.

## Adding a future cutover

The payoff of the declarative engine: the common case needs **zero new Go**.

1. Append ONE entry to **`charly/migrations.cue`** with a `version:` **strictly greater** than the current HEAD, expressing the transform as an `ops:` list (`rename_key` / `delete_key` / `remap_scalar` / `move_key`).
2. Bump `#SchemaVersion` in **`charly/schema/version.cue`** to that same CalVer.
3. Run **`task cue:gen`** to regenerate `charly/spec/version_gen.go`.

That is the whole common case — no bespoke migrator type, no registry function, no per-migrator Go file. Only a **structural reshape the four ops can't express** additionally registers ONE `goHooks` entry (a Go function named by the step's `apply:` field). Update the HEAD-CalVer fixtures + the repo's own versioned YAML in the same change.

The operator command never changes — it stays `charly migrate`.

**The validated schema is CUE-single-source.** The `@go()`-annotated `charly/schema/*.cue` defs are the sole source for the Go param structs (generated into `charly/spec` by `task cue:gen`); a wire-key change is a CUE edit first, then `task cue:gen`, then — only if it breaks existing on-disk configs — a migration-table entry here (plus the `#SchemaVersion` bump above). A pure codegen refactor that leaves every authored wire key untouched needs NO migration entry and NO `version:` bump. See the `/charly-internals:go` recipe "How to change the charly.yml schema (CUE is the single source of truth)".

### Standing rule: a schema/format change bumps `version:` AND mints a git tag

Any change to the YAML schema or composition format (a key rename, a deleted key, a new key shape) is a hard-cutover that MUST:

1. **Bump the `#SchemaVersion` CalVer** — edit `charly/schema/version.cue`, run `task cue:gen`, and append the matching entry to `charly/migrations.cue`. The load-time gate then rejects any not-yet-migrated config with a `Run: charly migrate` hint, so every reader sees the new format. Raising `#SchemaVersion` WITHOUT the migration-table entry (or vice-versa) is forbidden — and `version:` is NEVER set above `LatestSchemaVersion()` (newer configs hard-fail at load).
2. **Mint a fresh per-push git tag** on the landing push — `v<YYYY.DDD.HHMM>` from the push moment (see "Per-push release git tags" above). The tag and the `version:` bump are decoupled: the tag marks the push, `version:` marks the schema. A schema cutover happens to do BOTH at once, but a content-only push (no schema change) still mints a tag at an unchanged `version:`.

## Idempotency

Running `charly migrate` twice is a no-op: after the first run the config is stamped at HEAD, so the second run hits the floor gate's "at HEAD → nothing to migrate" branch. Every op is itself idempotent (a rename with no matching key does nothing). The migration table's own invariants — every entry a valid `#Migration`, versions strictly ascending and unique, HEAD == `#SchemaVersion` — are validated against CUE at process start.

## See Also

- `/charly-image:layer` — the node-form candy schema migrations produce
- `/charly-image:image` — `image:` entries + `charly box build/validate/inspect`
- `/charly-core:deploy` — the deploy entries a migration may rewrite
- `/charly-local:local-spec` — `kind: local` templates
- `/charly-build:secrets`, `/charly-build:settings` — the credential schema
- `/charly-internals:go` — loader internals (`LoadUnified`, `ParseCalVer`, the `gateSchemaVersion` load gate, the `charly/migrate_engine.go` op-walker)
- `/charly-internals:cutover-policy` — why hard-cutover + a single idempotent `charly migrate` is the required shape
