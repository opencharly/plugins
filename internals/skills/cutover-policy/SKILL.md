---
name: cutover-policy
description: |
  Authoritative reference for the "Hard Cutover by Default" policy governing
  schema changes, API renames, and deprecations. Forbidden patterns, required
  deliverables, rationale, examples from this repo, and the no-exception
  enforcement: plans are authored as full-scope single-phase cutovers and
  executed end-to-end regardless of estimated time, context, or scope.
  MUST be invoked when planning or reviewing any breaking change to Go types,
  YAML field names, CLI flags, or OCI labels.
---

# cutover-policy

Every schema change, API rename, or deprecation in OpenCharly ships as a **single hard-cutover PR**. This applies to BOTH code (Go types, exported functions, CLI flags, OCI labels) AND config (charly.yml, charly.yml, vm.yml field names and shapes).

A cutover may NEVER be phased — not at plan authoring, not at execution. There is no pre-approval split, no post-approval split, no phased rollout, no grace period, no "author it as two plans" fallback. Plans are authored as full-scope, single-phase cutovers regardless of estimated time, scope, or context. Every cutover executes end-to-end through R10 in the SAME conversation. ALWAYS push as far as you can; compact context and continue, as many times as it takes. An approved plan is a CONTRACT; implement it as written.

This skill is the source of truth for the policy. `CLAUDE.md` links here rather than re-stating the full policy inline. The project's `UserPromptSubmit` hook at `.claude/hooks/runtime-verification-reminder.sh` names the full R0-R10 + RDD + ADE roster as second-pass triggers (a pointer roster per the hooks doctrine, never rule-body copies) and fires at every user prompt.

## One phase, many tasks, one cutover — the workflow

**A "phase" is the whole cutover. "Tasks" are the breakdown inside it.** Never treat tasks as separate phases with their own sign-off.

1. **Plan**: write a plan file that describes the cutover as ONE phase. Decompose into tasks with `TaskCreate`. The plan file names the cutover, not a sequence of cutovers.
2. **Implement**: execute every task in the same working tree. **Prove the highest-risk unknowns on a live `disposable: true` bed FIRST (Risk Driven Development — never trust a skill / CLAUDE.md / code for a high-risk call; the archetypal one is whether this layer composition, at its latest versions, builds / deploys / runs together).** Transitional aliases, legacy-accepting code paths, or temporary dual-dispatch are permitted DURING implementation. They MUST be deleted BEFORE the R10 acceptance run — not merely before commit. R10 is the fresh-rebuild gate against the FINAL code; a transitional / legacy-accepting / dual-dispatch path still present when the R10 acceptance run executes means R10 verified a state that will NOT ship, and the deletion then rides untested into the commit — the exact R5 silent-skip regression. Delete every such path FIRST, THEN run the R10 acceptance gate. (Mid-flight smoke / RDD verification runs WITH transitional code present are encouraged — they never authorize the commit; only the final-code R10 acceptance run does.)
3. **Test at the end, not between tasks**: run unit tests, `charly box build`, `charly bundle add` + `charly check live`, and the R10 fresh-rebuild re-verification AFTER all tasks are marked complete. Testing between tasks is cheap smoke-confirmation; the acceptance gate is the full-stack run against the final, transitional-free code (every transitional / legacy / dual-mode path already deleted — see step 2).
4. **Ship or fix**: if any verification step fails, fix it in the same working tree and re-run the full verification. Do NOT commit a partial state.

**Forbidden**: "Phase 1 landed, Phase 2 pending" as a stopping point. That leaves the system half-migrated — legacy paths live alongside new paths, migrations not yet run, tests passing for some beds and not others. Every historical instance of that pattern in this project left dead code and untested integration points that bit users later.

**Splitting a cutover across conversation turns is ABSOLUTELY FORBIDDEN, with NO exception — at plan authoring or at execution.** Once a plan is approved, it executes end-to-end through R10 in the same conversation. ALWAYS push as far as you can. Compact context and continue, as many times as it takes. Time, context space, session budget, scope size, and "the work turned out to be large" are NEVER valid stop reasons.

Do not propose phasing, narrowing, or scope reduction at plan-authoring time. Do not negotiate a split mid-execution. Do not silently downgrade. Do not widen, re-approach, or otherwise rewrite the contract mid-execution either — the plan is fixed once approved, and the ONLY legal change is to STOP and ask. An approved plan is a CONTRACT; implement it as written. The ONLY valid stop conditions, at any stage, are (a) an error you cannot resolve that requires user input, or (b) the plan contradicts itself, CLAUDE.md, or a loaded skill — STOP and ask in either case; do NOT commit a partial state.

## Blocking vs non-blocking surfaced issues — what stays in this cutover, what spawns the next

The one-phase rule forbids splitting a SINGLE cutover's scope across turns or plans. It does NOT forbid a genuinely separate issue, surfaced mid-cutover, from getting its own cutover. Classify every issue the cutover surfaces:

- **Blocking** — the current change is incorrect, incomplete, or unsafe without the fix. It is part of THIS change's scope. Fix it in the SAME working tree and prove it under the CURRENT cutover's R10. It can NEVER be split out — that is the forbidden phasing.
- **Non-blocking** — the current change is correct AND complete without the fix, and the issue is genuinely separable from it. Fix it IMMEDIATELY — but as its OWN cutover with its OWN full R10, opened the moment the current cutover is R10-passed and committed. This is not "Phase 2" and not a "follow-up / someday" TODO: it is a distinct change, done now, fully verified, leaving no window of unverified brokenness on `main`.

The discriminator: *would shipping the current cutover WITHOUT this fix leave the tree correct and the cutover's claim true?* Yes → non-blocking (its own immediate-next cutover). No → blocking (this cutover). Unsure → blocking. Backports / cherry-picks are the canonical non-blocking example: never part of the current cutover's post-execution flow, each is its own atomic, fully-R10'd cutover you open automatically when needed, pausing only if the backport target or release strategy is a genuine crossroad.

**Objective test for "separable".** The issue is separable ONLY if the current cutover's OWN R10 (its check-coverage + fresh-rebuild) passes and proves the cutover's claim WITHOUT the fix — the fix is neither exercised by, nor changes the verdict of, this cutover's test coverage. A fix that would alter this cutover's R10 result or its check-coverage gate is BLOCKING.

**This does not loosen the no-split rule.** "No pre/post-approval split" and "no author-it-as-two-plans" forbid carving ONE change's scope into two to avoid doing it all now. The non-blocking path applies to a DIFFERENT, separable change — one this cutover surfaced, or any other issue you find — never to the current change's own scope. You open that next cutover autonomously (you do not wait for authorization); you pause to ask only at a genuine unexpected/unplanned crossroad. Mislabeling a blocking issue "non-blocking" to ship faster is the forbidden split wearing a disguise; when unsure, it is blocking. (See CLAUDE.md R2 — this section operationalizes the blocking/non-blocking half of it.)

## Forbidden patterns (by default)

- **Backcompat unmarshalers** that accept both old and new YAML forms.
- **`deprecated.go` shims** or type aliases that re-export removed identifiers.
- **Silent upconverters** that rewrite stale configs at load time.
- **Dual-mode code paths** where both the old and new surface work simultaneously.
- **"Phase 2 cleanup" comments** or TODOs for work that the cutover PR was supposed to complete.

Each of these has a specific failure mode that has occurred historically: the first three drag legacy-state complexity forward indefinitely; the fourth multiplies the test matrix; the fifth is the anti-pattern `R2` in `CLAUDE.md` forbids on a per-plan basis (no "pre-existing" / "out of scope" / "follow-up PR" classifications). Every one of these patterns is deleted BEFORE the R10 acceptance run, not merely before commit — the acceptance run must exercise the final, transitional-free code (the step-2 timing rule above; CLAUDE.md "Hard Cutover by Default").

## Required for every breaking change

- A new **migration-table entry** in `charly/migrations.cue` (a declarative `ops:` list, or an `apply:` `goHooks` hook for a structural reshape) PLUS a matching `#SchemaVersion` bump in `sdk/schema/version.cue` (the sdk repo — landed + tagged first, see `/charly-build:migrate`), applied via `task cue:gen`; the entry's CalVer is strictly greater than the current HEAD. Every cutover is one idempotent step applied by the core op-walker on the one `charly migrate` command — there are no per-cutover sub-verbs. Running `charly migrate` twice is a no-op. See `/charly-build:migrate`.
- A **fresh release git tag** `v<YYYY.DDD.HHMM>` (current UTC push time) on the cutover's push — ONE per push, **decoupled** from the `charly.yml` `version:` field (the schema version, bumped only when a cutover raises `#SchemaVersion`). Tag EVERY push, including one that does NOT bump `version:` (content removal — a submodule extraction, an image drop). Tags are **immutable** — only ever added, never moved or force-pushed. Every component is fixed-width zero-padded (4-digit year, 3-digit day-of-year, 4-digit HHMM) so tags sort chronologically under a plain alphanumeric sort; compute `v$(date -u +%Y.%j.%H%M)`. Each charly-project repo (one with `charly.yml`) is tagged at its own push time; `plugins` / `pkg/arch` are exempt. See `/charly-build:migrate` "Per-push release git tags" and CLAUDE.md "Post-Execution Policies".
- **Hard load-time errors** for any residual legacy field, with a one-line remediation hint pointing at the migration command.
- **Deletion — in the same PR** — of every Go type, function, CLI flag, OCI label, YAML field, skill doc paragraph, and test fixture that references the removed surface.
- **Stale-reference sweep (R5).** Every reference, comment, docstring, error message, skill paragraph, migration help-text, test fixture, and hook string naming a deleted identifier MUST be updated or deleted in the same commit. After commit, `git grep '<deleted-id>'` returns ONLY historical mentions in `CHANGELOG/` or migration help-text.
- **A `CHANGELOG/` entry** in the repo's per-CalVer file (`CHANGELOG/<YYYY.DDD.HHMM>.md`, the version shared by the changelog filename and the release tag) recording the cutover narrative. Historical content lives ONLY in the repo's `CHANGELOG/`; CLAUDE.md and the skills state the new standing rules forward-looking, with no history. See CLAUDE.md "Where things are documented".
- **Engineering-discipline gates (R1–R5).** See `/charly-internals:strict-policy`. Every failure during the cutover triggers `/charly-internals:root-cause-analyzer` BEFORE any remediation (R1). Every issue surfaced is fixed in the cutover or escalated (R2). Duplication is refactored on first surface (R3). Workarounds are forbidden (R4). Stale references are swept (R5).

## Rationale

Phased migrations accumulate mid-state complexity that, in practice, rarely gets removed. "We'll clean up in Phase 2" is a fiction that the history of this project has shown over and over. Making hard cutover the default across the project closes the loophole where this behavior sneaks in via PRs whose plans didn't explicitly call for a clean cutover.

## No exception clause

There is no pre-approval split, no post-approval split, no phased rollout, no grace period, no "resume in the next session", no "author it as two plans" fallback. Plans are authored as full-scope, single-phase cutovers regardless of estimated time, scope, or context. Phase / scope / time concessions are FORBIDDEN at plan authoring AND at execution.

Every cutover — regardless of estimated effort — runs as ONE phase in the SAME conversation through R10. ALWAYS push as far as you can. Compact context and continue, as many times as it takes.

The ONLY valid stop conditions, at any stage, are:

1. An error you cannot resolve that requires user input.
2. The plan contradicts itself, CLAUDE.md, or a loaded skill.

In either case STOP and ask. Do NOT silently downgrade scope, narrow tests, abbreviate the R10 matrix, or commit a partial state. An approved plan is a CONTRACT; implement it as written.

Forbidden internal-voice triggers (each is a confession, NOT a defence):

- "this is too large for one turn"
- "we should split this into two plans"
- "session budget concerns mean ..."
- "to fit context space ..."
- "for tractable wall-clock ..."
- "I'll narrow scope just for this canary ..."
- "let me ask whether to phase it"

If you catch yourself forming any of those: STOP forming them. The plan executes as written.

## What a clean cutover PR looks like

One PR, one commit, with these deliverables:

- **Code deletions** — every Go type, struct field, function, and label constant for the removed surface, deleted (not deprecated).
- **Schema deletions** — every removed YAML field rejected by the loader with a hard error.
- **Replacement surface** — the new types / schema / deploy target that supersede the deleted ones.
- **Migration** — one idempotent migration-table entry (`charly/migrations.cue`) that harvests legacy fields into the new shape, preserves pre-existing user keys, and never clobbers customizations.
- **Load-time error** — old projects loading under the new code get a hard error naming the legacy field and pointing at `charly migrate`.
- **Documentation refresh** — every referring skill revised in the same sweep; no stale references to any deleted identifier in `plugins/`, `README.md`, or `CLAUDE.md` (R5 grep self-test).
- **Test deletions** — fixtures and assertions exercising the legacy surface removed; new fixtures exercise the replacement.
- **CHANGELOG entry** — the cutover narrative written to the repo's per-CalVer file `CHANGELOG/<YYYY.DDD.HHMM>.md` (the version shared by the changelog filename and the release tag); the repo's `CHANGELOG/` is the only home for its history.

The commit uses the Conventional Commits `!` breaking-change marker; the body lists every deleted identifier, every removed YAML field, and every updated test. `charly migrate` is runnable against old projects from that commit forward, with no additional steps.

See `CHANGELOG/` for the catalog of past cutovers that followed this shape — each took the same three steps: **delete old surface + publish migration + hard load error**.

## When the policy might not apply

- **Purely additive changes** — new field that defaults to "off" with no removal of existing surface. No cutover needed; just add it.
- **Internal refactoring** — a Go function rename that isn't part of any stable API. No cutover needed; normal refactor rules apply.
- **Bug fixes** — behavior change without schema or API change. No cutover.
- **Documentation-only changes** — `*.md`, comment-only edits, or a submodule pointer bump to an all-documentation submodule commit, with zero behavior change. No hard-cutover machinery to run; the gate is the non-runtime standards (CLAUDE.md "Documentation-only change class") and the honest tier is `documentation reviewed`. R1–R5 still apply — a stale-doc divergence is still an incident (R1), swept claim-keyed (R5).

The policy kicks in when the change is **visible to consumers** (YAML authors, other Go packages, OCI-label readers) AND removes something that was previously usable.

## Cross-References

- `/charly-build:migrate` — the single `charly migrate` command, its CalVer schema versioning, and the CUE-anchored declarative migration table
- `/charly-internals:vm-spec` — example output of a cutover (new types replacing deleted ones)
- `/charly-internals:capabilities` — example of coordinated label-map cleanup during a cutover
- `/charly-internals:install-plan` — shared IR that survived the cutover unchanged (non-example — additive extension of the DeployTarget surface)
- CLAUDE.md "Hard Cutover by Default" — summary pointing at this skill

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM in vm.yml.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See CLAUDE.md R1–R10.
