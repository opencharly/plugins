---
name: git-workflow
description: |
  Use when committing, branching, pushing, merging, tagging, creating PRs, or
  approving/merging PRs with gh — the feat/-branch, R10-gated, never-force-push
  landing workflow across the main repo + the plugins submodule + box/<distro>
  submodules. Covers sync-to-upstream, branch/worktree pruning, the fork+PR path
  for contributors without write access, and cross-repo @github landing order.
---

# git-workflow — branch-per-change, R10-gated auto-landing

Every change to an charly-project repo follows ONE landing discipline. The **R10
pass is the sole gate**: nothing is committed, pushed, merged, or tagged on
unverified state, and once R10 passes the landing is automatic — no per-change
manual "push" step. This skill is the mechanics; CLAUDE.md "Post-Execution
Policies" carries the mandate, `/charly-internals:cutover-policy` the one-phase rule,
`/charly-build:migrate` the schema-version/tag coupling.

## Non-negotiable invariants

- **NEVER force-push.** No `git push --force`, no `--force-with-lease`, on ANY
  branch (`feat/` included) in ANY repo, ever. The whole flow is designed so a
  force push is never needed: `main` only fast-forwards; tags are add-only;
  `feat/` is pushed once at landing.
- **R10-gated.** Commit/push/merge/tag happen only after R10 PASS. A rule
  violation or R10 FAIL ⇒ none of them happen (fix in the same tree, re-run R10).
- **Zero warnings.** R10 is NOT successful while ANY warning remains — resolver
  newest-wins warnings, build, `charly box validate`, `charly check`, or deploy
  warnings. Every warning is fixed before R10 passes (a version-mismatch warning
  is cleared with `charly box reconcile`; any other warning triggers
  `/charly-internals:root-cause-analyzer` then a real fix). "Warning" is never an
  acceptable end state — it is an R10 failure (strengthens R1).
- **Atomic.** One commit per repo per cutover (the cutover-policy "one phase").
- **Tree-safety before destructive actions (R6).** Always check `git status` +
  `git stash list` before any destructive working-tree action — `git stash`
  discards in-progress work; `rm` on a tracked file is destructive. When the
  sandbox blocks an action, read the reason and find a non-destructive
  alternative — never work around it with a cleverer command.
- **Right worktree — pin ONE absolute path for the whole edit→commit→land
  sequence.** Before branching, staging, or committing, confirm the worktree you
  are driving is the SAME one your edits landed in: `git -C <path> rev-parse
  --show-toplevel` must equal the path you edited, and `git -C <path> status
  --short` must list those edits. Under symlinked or near-twin sibling worktrees —
  a parent dir that is itself a symlink (`~/projects` → `~/Sync/projects`), or
  look-alike names such as `…/charly` vs `…/<other-worktree>` — `cd`-ing to the
  wrong sibling makes `git switch -c` + `git commit` run against a CLEAN tree and
  report "nothing to commit", silently landing nothing (or worse, work in the
  wrong repo). Never change the path spelling mid-sequence. An unexpected "nothing
  to commit" / "working tree clean" right after you edited a file is the signature
  of this mistake — STOP and re-verify `--show-toplevel` before retrying (blind
  retry is an R1 violation).
- **Check-coverage.** R10 does not pass unless the change ships the test coverage
  that PROVES its functionality (`check:` checks for new/changed layers & images,
  Go tests for `charly` code) AND the live run exercised it. A change whose new
  functionality has no test that would FAIL without it is not landable.
- **Tags only on `charly.yml` repos** — plus the sdk contract repo, which tags
  under its own Go-module scheme `v0.<YYYYDDD>.<HHMM stripped>` (B2 step 0).
  `plugins` and `pkg/arch` are tag-exempt.

## B1 — the branch-per-change loop (write access)

```bash
# sync-before-start (see B4): branch off up-to-date main
git fetch origin --prune --tags
git switch main && git merge --ff-only origin/main
git switch -c feat/<slug>            # slug = kebab summary of the change

# ... implement the whole cutover; run beds freely throughout to VERIFY
#     (verify before you change — Risk Driven Development: prove high-risk
#     assumptions on a bed first); the COMMIT is gated on the full final-code
#     live test (pasted), which runs at the end ...

# on R10 PASS, automatically and in order:
VER=$(date -u +%Y.%j.%H%M)               # compute the CalVer ONCE — shared by the changelog file AND the tag
# write the cutover narrative to CHANGELOG/$VER.md (one changelog file per CalVer release)
git add <only the cutover's files> "CHANGELOG/$VER.md"   # never the in-flight state of unrelated work
git commit -m "<conventional commit>  ...  Assisted-by: Claude (<tier>)"
git push origin feat/<slug>
git switch main && git merge --ff-only origin/main   # re-sync; if main advanced, see below
git merge --ff-only feat/<slug>
git tag -a "v$VER" -m "<subject>" HEAD   # SAME CalVer as CHANGELOG/$VER.md — file and tag always match
git push origin main --follow-tags
git branch -d feat/<slug> && git push origin --delete feat/<slug>
```

A tag-exempt repo (`plugins`, `pkg-*` — no `charly.yml`) still writes `CHANGELOG/$VER.md`
with the same `VER=$(date -u +%Y.%j.%H%M)` stamp; it just skips the `git tag` step. So
EVERY landing in EVERY repo produces exactly one per-CalVer changelog file; taggable repos
additionally mint the matching `v$VER` tag.

If `main` advanced between branch-start and landing, the `--ff-only` merge refuses
(that's the safety property — never a force). Rebase `feat/` onto the new `main`,
**re-run R10**, then ff-merge. `feat/` is pushed once at landing, so a
rebase-then-push collision can't normally arise; in the rare case `feat/` was
already pushed and then rebased, update the remote with
`git push --delete origin feat/<slug>` followed by a fresh push — NEVER `--force`.

## B4 — sync to upstream + prune (per repo: main, sdk, plugins, box/*, pkg/*)

- **Sync-before-start / before-landing.** `git fetch origin --prune --tags`; ff
  local `main` to `origin/main`. Never force-reset a diverged local `main` — if it
  cannot fast-forward, STOP + run `/charly-internals:root-cause-analyzer`.
- **Switch-to-upstream check.** Before committing, confirm `origin` is the
  canonical upstream and the branch about to merge targets the upstream `main`
  (not a stale fork/branch). On mismatch, STOP and surface it.
- **Prune merged branches.** `feat/` is deleted at landing (B1). Sweep leftovers:
  `git branch --merged main` → delete local; `git fetch --prune` drops
  remote-tracking refs deleted upstream; `git branch -r --merged origin/main` →
  `git push origin --delete` the merged remote `feat/*`. **Only ever delete
  branches confirmed `--merged`**; never `-D` (force-delete) an unmerged/abandoned
  branch without operator confirmation — it may hold unlanded work.
- **Worktree hygiene.** `git worktree list` to inventory; `git worktree prune` to
  clear stale admin entries. Remove an agent `isolation: worktree` after its
  change lands. Before reusing a long-lived worktree, ff its base to `origin/main`.

## B2 — multi-repo / multi-worktree coordination

One logical change spanning several repos uses the **same `feat/<slug>` in each**
(main, `sdk`, `plugins`, `box/<distro>`), so the branches correlate. R10 runs against the
**assembled superproject** (submodule pointers at the `feat/` commits) — the whole
change is verified before anything merges. Then land in **dependency order**:

0. the **sdk contract repo** (`github.com/opencharly/sdk`, submodule `sdk/`) —
   commit → push → tag `v0.<YYYYDDD>.<HHMM leading-zeros-stripped>` (its
   Go-module tag scheme; the superproject `vYYYY.DDD.HHMM` form is not a valid
   Go module version — e.g. superproject `v2026.185.0751` ⇄ sdk
   `v0.2026185.751`) — whenever the cutover touched sdk content;
1. each `box/<distro>` submodule — commit → `--ff-only` merge → tag (it has
   `charly.yml`) → push;
2. `plugins` — commit → `--ff-only` merge → push (**no tag**, no `charly.yml`);
3. the superproject — stage the now-merged submodule pointers (a touched sdk:
   the `sdk` gitlink bump PLUS the `charly/go.mod` require version — in-tree
   resolution rides `replace github.com/opencharly/sdk => ../sdk`, so the
   require version matters only for out-of-tree consumers, but it is staged
   here) → atomic commit → `--ff-only` merge → tag `main` → push.

**Submodule-pointer-bump safety (step 3) — bump AFTER the switch, then stage AND
verify.** A `git switch` / `git checkout` re-materializes each submodule at the
gitlink the *target branch* records, silently discarding an **unstaged**
working-tree pointer bump (it happens even with `submodule.recurse` unset — an
unstaged gitlink is not carried across the switch). So bumping the pointer
*before* `git switch -c feat/<slug>` — or merely `git -C <sub> checkout <new>`
without `git add` — drops it from the commit, and a `git add <sub>; git commit`
afterward stages nothing because the working tree was reset to the old pointer.
Always, in order: (a) create/switch to the landing branch FIRST; (b) THEN
`git -C <sub> checkout <new-commit>` + `git add <sub>`; (c) VERIFY it is staged —
`git diff --cached --submodule=short <sub>` must print `<old>...<new>`; (d) after
committing, confirm the commit records it — `git show --stat` lists `<sub>` and
`git ls-tree HEAD <sub>` shows `<new>`. A pointer-bump commit whose `--stat` omits
the submodule is the silent-drop failure. If it was already pushed, land a NEW
pointer-bump commit (NEVER amend/force-push).

**Attribution of the pointer-bump commit — derived from what it points at.** When
the bumped submodule commit is itself all-documentation (a skill / `*.md` edit),
the superproject pointer-bump commit IS the Documentation-only change class and
lands at `documentation reviewed`: `pre-commit-gate.sh` recurses into the
submodule's own `old..new` diff to certify it (objects must be present locally; a
bump it cannot certify is rejected). A bump that integrates submodule CODE is a
code class and takes a runtime tier, the docs riding along. So a docs-only skill
cutover lands `plugins` (the `*.md`) at `documentation reviewed`, then the
superproject pointer bump at `documentation reviewed` too — both halves honest, no
runtime tier borrowed.

This mirrors the submodules-first push order. A change developed in a git worktree
keeps its `feat/` branch in the worktree; the ff-merge targets the canonical
repo's `main`; the worktree is removed after. Concurrent worktrees on one repo
each use a distinct `feat/` slug. **For the full multi-worktree end-to-end — which
path lands `main` when it lives in ANOTHER worktree, the doc-tier `git -C`
literal-path rule, and the mandatory post-landing worktree refresh — see B7.**

## B3 — agent teams on ONE shared tree (no worktree)

When an agent team parallelizes work, **the check bed is the unit of isolation,
not a worktree**. Each teammate owns a disjoint check bed's SOURCE files;
distinct beds get distinct container/VM/image names; the lead assigns each
disjoint host ports too (the loader does NOT check ports — an overlap fails the
second bed at deploy), and a bed pins an image → layers → files, so bed-ownership
already isolates the source files each teammate edits. **Teammates edit; a
PERSISTENT owner runs every full `charly check run <bed>`** as a `run_in_background`
task — the lead's persistent session, a background agent, or (interactive tmux) a
split-pane teammate; an in-process teammate CANNOT (its bg dies on yield).
Teammates therefore share ONE working tree on ONE `feat/<slug>` branch:

- Teammates edit their bed-scoped files in the shared tree + run short foreground
  checks (`charly check box`) — never the full `charly check run`, and **never commit or
  push**. The lead runs the full beds and owns the single atomic commit, gated on
  the consolidated full final-code bed run (B1).
- Reserve a real `git worktree` (per `isolation: worktree`) only for genuine
  **same-file** concurrency that bed-ownership does not separate — not as the
  default for team parallelism.
- **Schedule longest-pole-first.** `charly check run` has no bed-level concurrency and
  no `charly` cap — the limit is host CPU/RAM/podman. The lead runs ALL full beds as
  concurrent background tasks; order by expected DURATION, not bed count: launch
  the slow VM/desktop beds first and overlap the cheap pod beds, so wall-clock ≈
  the slowest single bed, not the sum.
- **Freeze `charly/*.go` during the bed phase.** `charly`'s stale-binary freshness guard
  gates every heavy verb the instant any `charly/*.go` is newer than `/usr/bin/charly`,
  so a teammate editing Go mid-bed-run aborts every other agent's next
  build/deploy/check. For a SHARED-CORE (Go) cutover the lead lands the core
  first, runs ONE `task build:charly`, then fans out beds with Go frozen; a BED-LOCAL
  (YAML/candy/skills) cutover has no shared binary and needs no such barrier.

## B5 — PR path (no write access) + `gh` auto-approve

Detect permission: `gh repo view --json viewerPermission`
(ADMIN/MAINTAIN/WRITE → Mode 1, else Mode 2).

- **Mode 1 — write access:** the B1 direct path (ff-merge, tag, push, delete).
- **Mode 2 — fork + PR:** on R10 PASS, ensure a fork (`gh repo fork --remote`),
  push `feat/<slug>` to the fork, then
  `gh pr create --base main --head <fork>:feat/<slug>` with a body that pastes the
  R10 evidence and ends with `*Assisted-by: Claude (<tier>)*`. The PR is the
  deliverable; never force-push, never need upstream write.
- **`gh` auto-approve/merge (maintainer-side, with approve rights):** for an open
  PR, **fetch its head, review the diff, and run R10 against it**; ONLY on R10
  PASS (and only if the change ships its check/test coverage) `gh pr review
  --approve` then `gh pr merge --rebase --delete-branch` (rebase keeps `main`
  linear, matching ff-only), then tag the new `main` HEAD. **Never a blind
  approve** — no approval/merge of unreviewed or R10-unverified code, whoever
  opened it. Required status checks / branch protection are respected, never
  bypassed, never force-merged.

## B6 — cross-repo R10 when a change is referenced via `@github`

The resolver (`EnsureRepoDownloaded`) fetches a producer repo from the REMOTE at
the pinned ref, so a producer change on a local `feat/` branch is invisible to a
consumer's R10 — **a local branch is not enough**. Staged landing (no
local-override):

1. Develop producer (A) + consumer (B) on the same `feat/<slug>`.
2. **Land the producer FIRST:** run A's own R10, ff-merge, **tag A `v<CalVer_A>`**,
   push — now an immutable, fetchable remote tag.
3. **Repoint the consumer:** `charly box reconcile` rewrites B's `@github.../A:...`
   pins to `v<CalVer_A>` (see `/charly-build:reconcile`).
4. **Authoritative consumer R10 against the real tag:** B's R10 now fetches A from
   the pushed `v<CalVer_A>` — verified against exactly what ships.
5. **Land the consumer** (ff-merge, tag B, push).
6. **New candy:** a new candy has no standalone R10 — its gate is the consuming
   image's build. A lands a **provisional** `v<CalVer_A>` (layer + `go test` /
   `charly box generate` smoke); step 4 (B's image R10 against that tag) is the real
   gate. On failure, fix A, land a **new** tag (immutable + accumulate — never
   move the old one), re-reconcile, re-run step 4.

Each repo gets ONE R10 against ITS final code — the producer against its own
change, the consumer against the producer's landed tag — and repos land
producer→consumer. Multi-level chains (A→B→C) recurse the same way.

## B7 — Multi-worktree landing + refresh (the canonical end-to-end)

When this project is driven from multiple git worktrees sharing one `.git`, only ONE
worktree can have `main` checked out at a time. Every "push + update all worktrees" follows
this EXACT ordered sequence; deviating is how the ad-hoc disasters happen. It composes
B1 (branch loop), B2 (per-repo order + pointer-bump safety), B4 (sync/prune).

**0. Pre-flight (worktree safety).** `git worktree list` → note which worktree holds
`main`. Pin ONE worktree for the whole edit→commit→land sequence; drive every step with
a **literal absolute path** `git -C /abs/path …`. NEVER a leading `cd`+`\`-continued
chain (it scopes every later command into the submodule) and NEVER a shell variable for
a path — **shell variables do NOT persist between Bash tool calls**, so a `WT=…` set in
an earlier call is EMPTY later and `git -C "$WT/plugins"` silently becomes `git -C
/plugins` (this was a real failure). Verify: `git -C /abs rev-parse --show-toplevel` ==
the path you edited AND `git -C /abs status --short` lists your edits.

**1. Sync-before-start.** `git fetch origin --prune --tags`; ff local `main` to
`origin/main` (B4).

**2. Land in dependency order, same `feat/<slug>` in every repo** (sdk when touched →
box submodules → plugins → superproject). Per-repo mechanics = B2 + B1; pointer-bump
safety = B2 step 3.
Two proven additions:
  - **plugins docs commit at `documentation reviewed`: `git -C <LITERAL-abs-plugins>
    commit …`.** RDD-proven on the live gate: a literal `-C` scopes `pre-commit-gate.sh`
    to the plugins all-docs index in ONE shot (it passes even while the superproject has
    non-doc code staged, and recurses the submodule's `old..new` diff). Do NOT use a
    `$var` (may be unset → `git diff --cached --raw failed`); do NOT use `cd plugins &&
    git commit` (the gate fires BEFORE the in-command `cd`, so it inspects the
    SUPERPROJECT index and blocks on staged code). The literal `-C` removes the old
    "empty the other index first" dance entirely.
  - **box/<distro> re-stamp** (schema-HEAD bump): edit on the submodule's own `main`;
    **gate = `charly box validate` standalone** (a version-stamp change has no build
    behavior — building proves nothing); commit, annotated tag, push.

**3. Land `main` — it lives in ONE worktree, so NEVER `git switch main` elsewhere (git
fatals "already used by worktree"). Pick ONE path:**
  - **Path A (remote-mediated, from the work worktree):** `git push origin feat/<slug>`
    → `git push origin feat/<slug>:main` (a ff of `origin/main` — the worktree-safe
    `merge --ff-only`, NEVER a force) → tag + push tag → `git -C <main-wt> merge
    --ff-only origin/main` to advance the LOCAL `main` ref (`push :main` doesn't move it).
  - **Path B (drive the main worktree by path):** `git -C <main-wt> merge --ff-only
    feat/<slug>` (guard: `git -C <main-wt> status` clean + `git merge-base --is-ancestor
    <old-main> <feat-HEAD>`) → `git -C <main-wt> push origin main --follow-tags`.
    Advances local `main` automatically; pushes no remote `feat/`.

**4. Tags: annotated only** (`git tag -a v<…> -m "<desc>" HEAD`). `--follow-tags` does
NOT push a LIGHTWEIGHT tag → verify `git cat-file -t <tag>` == `tag` AND `git ls-remote
--tags origin <tag>` is non-empty.

**5. Reconcile (when box submodules were re-stamped).** Bump the superproject GITLINKS
`+1` to the re-stamped box mains (a separate superproject commit; B2 step-3 safety) — do
**NOT** bump the `@github` build pins: they lag deliberately, `charly box reconcile`
reports "already reconciled", and bumping them pulls multi-cutover producer drift (a
separate version-adoption cutover, NOT reconciliation).

**6. Refresh EVERY worktree — PART of landing, NEVER a follow-up (R2).** For each
worktree: the one on `main` → `git -C <wt> merge --ff-only origin/main`; each other →
`git -C <wt> checkout --detach origin/main`; THEN `git -C <wt> submodule update --init
--recursive`. The Skill tool serves skills from the MAIN worktree — a stale main
worktree silently serves STALE SKILLS to sessions, so refreshing it is mandatory. (A
` M <sub>` in a worktree used only for the ff-merge is this drift, not lost work.)

**Landing gotchas (each cost real time):** the **PreToolUse pre-commit-gate fires ONCE
per Bash call, BEFORE the command runs** → a `git reset && git commit` in ONE call fails
(the reset hasn't happened yet); split into separate Bash calls. `task build:charly`
dirties `pkg/arch/PKGBUILD` (makepkg `pkgver()`) → `git -C <pkg/arch> restore PKGBUILD`.
`git merge-base --is-ancestor A B` ERRORS if B's object isn't fetched (common for a
sibling-worktree submodule) → `git fetch` first; cross-check `git ls-tree origin/main
<sub>` before concluding "DIVERGED". A `git grep -- <submodule-path>` from the
superproject is a FALSE ZERO (git grep does not cross a gitlink) → `git -C <sub> grep`
for the R5 sweep.

## CalVer computation — one stamp, shared by the changelog file and the tag

`<YYYY.DDD.HHMM>` from the current UTC landing time. Every component is fixed-width
zero-padded (4-digit year, 3-digit day-of-year, 4-digit HHMM) so both the changelog
filenames and the tags sort chronologically under a plain alphanumeric sort. Compute
it ONCE and reuse it for the per-CalVer changelog file AND the tag, so they can never
disagree:

```bash
VER=$(date -u +%Y.%j.%H%M)               # the single CalVer stamp for this landing
# ... write CHANGELOG/$VER.md (staged into the commit) ...
git tag -a "v$VER" -m "<subject>" HEAD   # the tag mirrors the changelog file name
```

ONE fresh stamp per push (a repo accumulates many changelog files / tags), immutable
(only ever added), INDEPENDENT of `charly.yml` `version:` (the schema version, bumped
only by a cutover raising `#SchemaVersion` in `sdk/schema/version.cue`). Every
landing writes exactly one `CHANGELOG/$VER.md`; a repo WITH a `charly.yml` (superproject,
`box/<distro>`) additionally mints the matching `v$VER` git tag, while `plugins`/`pkg-*`
stay tag-exempt (changelog file only). A YAML schema/format change does BOTH: raise
`#SchemaVersion` (with its `candy/plugin-migrate/migrations.cue` entry) AND mint the tag. See
`/charly-build:migrate`.

## After landing — cleanliness + report

- **Working-tree cleanliness.** After commit + landing, `git status` is clean
  in every repo. Untracked files that aren't part of the cutover (test
  artifacts, build outputs) belong in `.gitignore`; if they aren't, that's its
  own immediate-next cutover, not part of this one.
- **Report format.** The final message states: what was committed (commit
  subject + hash, per repo), the confidence tier with the proof that supports
  it, what was pushed, and the pasted R10 outputs (exploratory +
  fresh-rebuild). The tier must match CLAUDE.md "AI Attribution", keyed to the
  change class (`/charly-check:check` "R10 gate by change class") — a
  Documentation-only change class commit lands at `documentation reviewed`,
  runtime classes at a runtime tier. A worked commit message:

```
Fix: Add fuse-overlayfs for container startup

Tested via overlay session on LOCAL system.

Assisted-by: Claude (fully tested and validated)
```

## If R10 fails

R10 failure is a return-to-implementation signal, not a stopping point:

1. Run `/charly-internals:root-cause-analyzer` BEFORE attempting any fix —
   blind retry is FORBIDDEN.
2. Fix in the SAME working tree — never a follow-up PR.
3. Re-run the FULL R10 from a fresh `charly update`, not just the failing
   piece — a fix that survives only the targeted re-run is a regression in
   waiting.
4. Commit only when R10 passes end-to-end on the FINAL code.

## Cross-References

- CLAUDE.md "Post-Execution Policies" — the mandate this skill operationalizes.
- `/charly-internals:cutover-policy` — one-phase, atomic-commit, R10-at-the-end.
- `/charly-build:migrate` — `version:` ↔ tag coupling, per-push tags, push order.
- `/charly-build:reconcile` — cross-repo `@github` pin alignment used by B6.
- `/charly-check:check` — the check-coverage gate (R10) every change must satisfy.
- `/charly-internals:root-cause-analyzer` — run on any R10 failure before re-trying.

## When to Use This Skill

Invoke before any `git` / `gh` action that commits, branches, pushes, merges,
tags, creates a PR, or approves/merges a PR — and whenever syncing to upstream or
pruning branches/worktrees across the main repo and its submodules.
