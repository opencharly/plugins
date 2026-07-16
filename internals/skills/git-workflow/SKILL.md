---
name: git-workflow
description: |
  Use when committing, branching, pushing, opening PRs, or landing a change with
  gh — the feat/-branch, R10-gated, PR-ONLY, agent-validated, never-force-push
  landing across the main repo, sdk/plugins submodules, and box distro
  submodules. A direct push to main is FORBIDDEN and mechanically disabled; a
  FRESH pr-validator agent validates the PR, merges it (squash), and tags. Covers
  sync-to-upstream, branch/worktree pruning, the fork+PR path, cross-repo @github
  landing order, and the CalVer-generated-at-merge rule.
---

# git-workflow — branch-per-change, PR-only agent-validated landing

Every change to an OpenCharly repo lands through ONE discipline: a **pull request**
that a FRESH `pr-validator` agent independently validates and merges. A **direct
push to `main` is FORBIDDEN and mechanically disabled** — GitHub branch protection
(`enforce_admins`) + the `pre-push-gate` block it in every repo. The **R10 pass
authorizes OPENING the PR, never a self-merge**: the two-step landing separates the
author (who opens the PR) from the fresh evaluator (who validates, merges, tags).
This skill is the mechanics; CLAUDE.md "Post-Execution Policies" carries the
mandate, `/charly-internals:cutover-policy` the one-phase rule, `/charly-build:migrate`
the schema-version/tag coupling, and `plugins/internals/agents/pr-validator.md` the
evaluator's own spec.

## Non-negotiable invariants

- **NO direct push to `main`.** `main` advances ONLY through an agent-validated PR
  merge. GitHub branch protection requires the `charly/pr-validator` status
  (posted by the fresh `pr-validator`) + a PR + linear history + `enforce_admins`;
  the `pre-push-gate` blocks every main-destination push locally. Organization-wide
  apply/verify is owned only by `opencharly/.github/scripts/branch-protection.sh`.
- **NEVER force-push.** No `git push --force`, no `--force-with-lease`, on ANY
  branch (`feat/` included) in ANY repo, ever. The flow never needs one: `feat/`
  advances only by ADDING commits (the author's change, any review-round fix commits,
  then the evaluator's merge-time version stamp) and the squash-merge collapses them;
  a stale `feat/` is brought up to date with `gh pr update-branch` (a merge, NOT a
  rebase-force); tags are add-only. `git commit --amend` on a PUSHED branch is
  therefore forbidden too — it diverges the branch and can only be published by a
  force-push. Amend only before the first push.
- **R10-gated.** R10 PASS authorizes OPENING the PR (with pasted evidence). The
  MERGE is gated on the fresh `pr-validator`'s green `charly/pr-validator`
  status — a rule violation or R10 FAIL ⇒ no green status, no merge (fix in the
  same tree, re-run R10, re-push; the status resets and the evaluator re-runs).
- **Zero warnings.** R10 is NOT successful while ANY warning remains — resolver
  newest-wins warnings, build, `charly box validate`, `charly check`, or deploy
  warnings. Every warning is fixed before R10 passes (a version-mismatch warning
  is cleared with `charly box reconcile`; any other warning triggers
  `/charly-internals:root-cause-analyzer` then a real fix). "Warning" is never an
  acceptable end state — it is an R10 failure (strengthens R1).
- **Atomic ON `main`.** ONE atomic cutover per repo lands as **exactly ONE commit on
  `main`**: the evaluator merges `--squash`, folding the author's change commit(s), any
  fix commits a review round added, and the mechanical version-stamp (the merge-time
  CalVer rewrite — see "CalVer") into a single commit whose message the evaluator
  composes. Atomicity is a property of `main`, NOT of the `feat/` branch — the branch may
  freely accumulate fix commits across review rounds, and `--squash` is what keeps `main`
  one-commit-per-cutover and linear. Two SEPARATE cutovers must never share one PR.
- **Update the PR; never close-and-recreate.** A PR is the unit of a cutover's review
  history. When a review demands changes, APPEND a commit and push it fast-forward — the
  status resets and the evaluator re-runs. Closing a PR is reserved for work that will
  NOT land at all (a disproven premise, an abandoned approach), never for iterating on
  findings. This is what makes the no-force-push rule livable: because `main` gets a
  squash, a branch carrying five fix commits still lands as one.
- **Tree-safety before destructive actions (R6).** Always check `git status` +
  `git stash list` before any destructive working-tree action — `git stash`
  discards in-progress work; `rm` on a tracked file is destructive. When the
  sandbox blocks an action, read the reason and find a non-destructive
  alternative — never work around it with a cleverer command.
- **Right worktree — pin ONE absolute path for the whole edit→commit→push
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
- **Post-commit staging verification — a multi-path `git add` with one bad
  pathspec can stage LESS than you intended, silently.** After EVERY commit,
  re-run `git status --short` (expect it empty, or only unrelated untracked
  paths) AND `git show --stat` (confirm every intended file is actually
  listed) — a `git add` invocation naming several paths where one is
  mistyped or stale can commit only the files that DID resolve while
  `git commit` still succeeds, producing a commit that would not even
  compile. Proven this session: an 8-file commit was caught missing files
  only by habitually re-checking `git show --stat`, not by any tooling
  that would have failed loudly on its own.
- **Check-coverage.** R10 does not pass unless the change ships the test coverage
  that PROVES its functionality (`check:` checks for new/changed layers & images,
  Go tests for `charly` code) AND the live run exercised it. A change whose new
  functionality has no test that would FAIL without it is not landable.
- **Every repo is tagged at merge.** The superproject, every `box/<distro>`,
  `plugins`, and `pkg/*` all mint `v<YYYY.DDD.HHMM>` on their own merged HEAD — the
  tag marks the MERGE, decoupled from any `charly.yml` `version:` schema field, so a
  repo needs no `charly.yml` to be tagged. The SOLE exception is the sdk contract
  repo, which tags under its own Go-module scheme `v0.<YYYYDDD>.<HHMM with ALL
  leading zeros stripped>` (B2 step 0) — **NOT an exemption but a hard Go-module
  requirement**: `v<YYYY.DDD.HHMM>` is not a valid Go module version (semver forbids
  a leading-zero segment — `0733`→`733` — and a `major ≥ 2` would force a `/vN`
  module-path suffix that breaks every `import github.com/opencharly/sdk`), so the
  stripped `v0.<…>` form is mandatory, not a choice.
  **A skipped tag is a DEFECT, not an exemption.** The pre-unification
  `plugins`/`pkg`-tag-exempt rule is RETIRED — a recalled prior or memory asserting it
  is STALE (it once shipped a `plugins` merge un-tagged); verify against THIS rule, never
  that belief. So the orchestrator VERIFIES the tag landed after EACH merge —
  `git ls-remote --tags origin v<VER>` non-empty — and, if the evaluator skipped it,
  BACKFILLS it ADD-ONLY on the merged HEAD (`git tag -a v<VER> -m "<subject>"
  <merged-HEAD>` + `git push origin refs/tags/v<VER>`); tags are immutable, so a backfill
  only ADDS one, never moves an existing tag.

## B1 — the two-step branch-per-change loop

**Step 1 — Author** (opens the PR; NEVER merges it):

```bash
# sync-before-start (see B4): branch off up-to-date main
git fetch origin --prune --tags
git switch main && git merge --ff-only origin/main
git switch -c feat/<slug>            # slug = kebab summary of the change

# ... implement the whole cutover; run beds freely throughout to VERIFY
#     (Risk Driven Development: prove high-risk assumptions on a bed first) ...

# on R10 PASS, open the PR (do NOT merge):
# write the cutover narrative to CHANGELOG/<placeholder>.md — a PLACEHOLDER CalVer
#   (any valid YYYY.DDD.HHMM; the evaluator OVERWRITES it with the merge-time VER).
git add <only the cutover's files> CHANGELOG/<placeholder>.md
git commit -m "<conventional commit> ...  Assisted-by: <Harness> <Full Model Name> (<confidence>)"
git push origin feat/<slug>                       # feat push — allowed by the gate
gh pr create --base main --head feat/<slug> \     # fill the PR template completely (single org source: opencharly/.github/.github/PULL_REQUEST_TEMPLATE.md — no per-repo copy)
  --title "<subject>" \
  --body-file <pr-body.md>
# STOP. Do NOT merge your own PR. Hand off to a FRESH pr-validator (Step 2).
```

**Step 2 — Fresh evaluator** (`plugins/internals/agents/pr-validator.md`, spawned
with NEW context): it independently re-validates the PR vs R0–R10 + the relevant
skills, posts `charly/pr-validator` on the head SHA, and ONLY on PASS
generates the merge-time CalVer, rewrites the version surfaces on `feat/` (the
`CHANGELOG` rename + any schema bump), re-posts the status on the new head,
`gh pr merge --squash --delete-branch`, and tags. Its inputs include the PR's
FULL comment thread, per the pr-validator spec's comment-intake rule — every
comment is investigated independently and considered in the verdict, never
granted or denied authority merely by existing (see
`plugins/internals/agents/pr-validator.md` "Comment intake", never restated
here). The author pastes the evaluator's verbatim verdict + what it
merged/tagged (paste-proof survives delegation). On FAIL the PR stays OPEN
and is **UPDATED IN PLACE** → the author R1-RCAs, fixes in the same tree,
APPENDS a fix commit, and pushes it fast-forward (status resets) → the
evaluator re-runs. **Never close a PR and open a replacement to carry a fix.**

Because the merge is a SQUASH and `main` is protected linear, `main` gains exactly
ONE commit per cutover — the author's change, any review-round fix commits, and the
version stamp, folded together.

### Concurrent landings — N open cutovers do NOT serialize beyond git itself

With several cutovers in flight (a multi-cutover program), **only two things are
inherently ordered: the merge instants (git — seconds each) and any real dependency
DAG between cutovers.** Everything else runs CONCURRENTLY, and no doc may mandate
more serialization than that without a technical reason:

- **Implementation** — one git worktree per cutover, per-worktree binaries for
  verification (`/charly-internals:agents` "Per-worktree binaries", proven), bed
  gates from multiple branches overlapping under the shared hardware ceiling.
- **Validation** — fresh `pr-validator`s run CONCURRENTLY across all ready PRs
  (each is an independent context; nothing couples them before the merge instant).
- **After each merge** — every still-open PR goes `BEHIND` (all three repos set
  `strict: true` require-up-to-date — KEPT deliberately: one shared Go package with
  no CI on `main` means merging a stale-base green PR opens a semantic-conflict
  blind spot; that is the technical reason, not doctrine). Recover with
  `gh pr update-branch` (never force-push), then a **risk-proportional DELTA
  RE-GATE** re-posts the per-commit status: compute the overlap
  `git diff --name-only <old-main>..main` ∩ the branch's touched files —
  EMPTY → rebuild + `go test ./...` + `golangci-lint run` + re-post (minutes);
  NON-EMPTY → additionally re-run the cutover's primary beds; a full roster re-run
  only when the overlap hits the cutover's risky paths. The ORIGINAL full R10
  against the branch's final code remains mandatory before the FIRST validation —
  the delta re-gate covers only the mechanical update-branch merge on top of an
  already-R10'd `main`.

**Gitlink ANCESTOR bump → `gh pr update-branch` flags CONFLICTING (recover
locally).** When the just-merged delta and a still-open PR both bump the SAME
submodule gitlink and one bump is an ANCESTOR of the other, GitHub's
`gh pr update-branch` does NOT auto-resolve it — it conservatively reports the PR
CONFLICTING instead of fast-forwarding the gitlink to the descendant. The
compliant recovery is the update-branch EQUIVALENT done LOCALLY: in the feat
worktree, `git merge origin/main` (git resolves the gitlink to the descendant
commit automatically), then push the result FAST-FORWARD. A MERGE, never a rebase;
no force-push — the exact constraints `gh pr update-branch` itself honors. **Then
VERIFY the merge resolved the gitlink FORWARD** — `git ls-tree HEAD <sub>` (or
`git diff --submodule=short origin/main..HEAD`) must show the DESCENDANT commit, never
the ancestor: a recovery that silently re-pins the OLDER submodule bump is the exact
regression this class produces (a sibling merge advances `main` mid-validation, then a
naive recovery reverts the gitlink to the older pointer). Only after the descendant-wins
check re-post the status and delta-re-gate as above.

**Multi-committer main advances — out-of-tree PRs from other committers.** The
orchestrator is NOT the sole source of `main` advances: another committer (a human
maintainer, a parallel session, an outside contributor via the fork+PR path) may
land an unrelated PR on `main` WHILE this plan's `feat/` branches are in flight. The
discipline above is main-advance-agnostic and applies to ANY merge regardless of
source — treat an out-of-tree merge IDENTICALLY to an internal one:
- **Detect proactively, not only reactively.** Fetch `origin/main` (and each
  submodule's `main`) before opening EACH PR and before each merge — do not rely
  solely on the orchestrator's own-merge broadcast. A `feat/` branch that goes
  `BEHIND` from an external merge is recovered exactly as above (`gh pr
  update-branch`, delta re-gate, forward-gitlink verify). `strict: true` is KEPT
  precisely for this: a stale-base green PR merged over an external advance opens a
  semantic-conflict blind spot, so the delta re-gate's overlap check
  (`git diff --name-only <old-main>..main` ∩ branch-files) is what makes an
  out-of-tree merge safe — EMPTY overlap → re-post; NON-EMPTY → re-run the primary
  beds. A teammate pushing while `BEHIND` an external merge updates its branch and
  reports the overlap for the orchestrator's delta-re-gate call.
- **Divergent-lineage submodule bump (not ancestor/descendant).** The
  descendant-wins rule above covers the common case (the external merge bumped a
  submodule to a DESCENDANT of our feat's pin). If an out-of-tree merge bumps a
  submodule to a commit NOT in our feat's gitlink ancestry (a divergent lineage — a
  different branch merged, or a revert), do NOT blindly descendant-wins:
  re-resolve the feat to the new `main`'s submodule commit, RE-RDD the affected
  cross-repo composition (the composition-at-latest-versions high-risk unknown —
  prove it on a `disposable: true` bed), and only then re-post status. A naive
  update-branch that re-pins the OLDER or divergent gitlink is the exact regression.
- **The rebase broadcast covers external advances too.** When the orchestrator
  detects ANY `main` advance — internal OR external — it broadcasts the rebase to
  every in-flight teammate and re-runs the per-merge delta re-gate over the
  external delta; the orchestrator OWNS external-advance detection (it is the one
  actor that fetches `origin/main` across all lanes).

### The cross-repo WIP landing sequence — commit-to-rebase without shipping unproven code

A multi-repo cutover hits a genuine tension: the WIP must be COMMITTED before a
rebase onto freshly-advanced mains (a submodule-spanning working tree makes
`git stash` unsafe — a gitlink stash can silently drop a submodule's in-progress
pointer, R6), yet a runtime-class commit gate demands LIVE proof of the FINAL code,
which does not exist until AFTER the rebase. Resolve it by committing at the tier
that is HONEST at each stage on an UNPUSHED branch, then re-stamping the tier once
the final code is proven — never by shipping anything pre-bed:

- **(a) Freeze + exploratory roster.** Freeze the WIP and run the EXPLORATORY bed
  roster against that frozen state (the `disposable: true` beds whose kinds match
  the change).
- **(b) Commit LOCALLY at the then-honest tier — do NOT push.** With the live
  runner having actually run and its output pasted, the honest tier is
  `analysed on a live system` (CLAUDE.md "AI Attribution"). Commit at that tier to
  create the rebase-able base. The commit stays LOCAL.
- **(c) Rebase onto the current mains.** Bring the branch onto the just-advanced
  `origin/main` of every repo, and REGENERATE every generated file from the merged
  sources (`task cue:gen`, codegen) — never hand-merge a generated artifact
  (generated-artifact drift is an R1 incident).
- **(d) Re-run the gates, re-freeze.** `go test` / `golangci-lint` / build /
  `charly box validate` on the rebased tree, then freeze again.
- **(e) FINAL roster on the rebased FINAL code.** The R10 acceptance roster runs on
  the rebased, transitional-free code — the state that will actually ship.
- **(f) Amend/reword to the EARNED tier, then push + open the PRs.** Re-stamp the
  commit's attribution tier to what the FINAL roster earned (`fully tested and
  validated` on a clean full pass). This amend is legal ONLY because the branch is
  UNPUSHED — the "amend only before the first push" invariant above. THEN push
  `feat/<slug>` and open the PRs (B1 step 1; multi-repo order = B2).

Nothing pre-bed ever ships, and every intermediate commit passes the PreToolUse
tier gate TRUTHFULLY at the stage it was made — the tier only ever moves UP, to
match proof that now exists.

## B4 — sync to upstream + prune (per repo: main, sdk, plugins, box/*, pkg/*)

- **Sync-before-start.** `git fetch origin --prune --tags`; ff local `main` to
  `origin/main`. Never force-reset a diverged local `main` — if it cannot
  fast-forward, STOP + run `/charly-internals:root-cause-analyzer`. (Local `main`
  now only ever fast-forwards to what agent-validated PRs merged remotely.)
- **Switch-to-upstream check.** Before opening the PR, confirm `origin` is the
  canonical upstream and the PR targets the upstream `main` (not a stale
  fork/branch). On mismatch, STOP and surface it.
- **Prune merged branches.** `feat/` is deleted at merge (`--delete-branch` +
  `delete_branch_on_merge`). Sweep leftovers: `git branch --merged main` → delete
  local; `git fetch --prune` drops remote-tracking refs deleted upstream. **Only
  ever delete branches confirmed `--merged`**; never `-D` an unmerged/abandoned
  branch without operator confirmation — it may hold unlanded work.
- **Worktree hygiene.** `git worktree list` to inventory; `git worktree prune` to
  clear stale admin entries. Remove an agent `isolation: worktree` after its change
  lands. Before reusing a long-lived worktree, ff its base to `origin/main`.

## B2 — multi-repo / multi-worktree coordination

One logical change spanning several repos uses the **same `feat/<slug>` in each**
(main, `sdk`, `plugins`, `box/<distro>`), so the branches correlate. R10 runs
against the **assembled superproject** (submodule pointers at the `feat/` commits)
— the whole change is verified before any PR is opened. Then land in **dependency
order**, each repo as its OWN two-step PR (author opens; fresh `pr-validator`
merges + tags):

0. the **sdk contract repo** (`github.com/opencharly/sdk`, submodule `sdk/`) — PR →
   evaluator merges → tag `v0.<YYYYDDD>.<HHMM leading-zeros-stripped>` (its
   Go-module tag scheme; the superproject `vYYYY.DDD.HHMM` form is not a valid Go
   module version — e.g. superproject `v2026.185.0751` ⇄ sdk `v0.2026185.751`) —
   whenever the cutover touched sdk content;
1. each `box/<distro>` submodule — PR → evaluator merges + tags (it has `charly.yml`);
2. `plugins` — PR → evaluator merges **+ tags `v<YYYY.DDD.HHMM>`** (no `charly.yml`,
   so no schema `version:` bump — but the tag marks the merge, same as every repo);
3. the superproject — stage the now-MERGED submodule pointers (a touched sdk: the
   `sdk` gitlink bump PLUS the `charly/go.mod` require version — in-tree resolution
   rides `replace github.com/opencharly/sdk => ../sdk`, so the require version
   matters only for out-of-tree consumers, but it is staged here) → PR → evaluator
   merges + tags `main`.

A producer PR must be **merged** (not merely green) before the consumer's pointer
bump — the superproject pointer must reference a commit that is on the submodule's
real `main`, which only the merge produces.

**A valid base is an ASSEMBLED PAIR, not a lone submodule advance.** A new consumer
cutover branches from a base that is valid only once BOTH halves have merged: an `sdk`
`main` advance is a valid consumer base ONLY after its superproject adaptation (the
gitlink bump + any `charly/go.mod` require) has ALSO merged. Branch a consumer off a bare
`sdk` main advance whose super side is still open and you pin a superproject state no
`main` records — the consumer's R10 builds against a half-assembled base and its pointer
bump references a commit `main` has never seen. Wait for the pair before treating a
producer advance as a base.

**Submodule-pointer-bump safety (step 3) — bump AFTER the switch, then stage AND
verify.** A `git switch` / `git checkout` re-materializes each submodule at the
gitlink the *target branch* records, silently discarding an **unstaged**
working-tree pointer bump (it happens even with `submodule.recurse` unset — an
unstaged gitlink is not carried across the switch). So bumping the pointer *before*
`git switch -c feat/<slug>` — or merely `git -C <sub> checkout <new>` without
`git add` — drops it from the commit, and a `git add <sub>; git commit` afterward
stages nothing because the working tree was reset to the old pointer. Always, in
order: (a) create/switch to the landing branch FIRST; (b) THEN `git -C <sub>
checkout <new-commit>` + `git add <sub>`; (c) VERIFY it is staged — `git diff
--cached --submodule=short <sub>` must print `<old>...<new>`; (d) after committing,
confirm the commit records it — `git show --stat` lists `<sub>` and `git ls-tree
HEAD <sub>` shows `<new>`. A pointer-bump commit whose `--stat` omits the submodule
is the silent-drop failure.

**Attribution of the pointer-bump commit — derived from what it points at.** When
the bumped submodule commit is itself all-documentation (a skill / `*.md` edit),
the superproject pointer-bump commit IS the Documentation-only change class and
lands at `documentation reviewed`: the fresh validator inspects the submodule's
own `old..new` diff to certify it. A bump that integrates submodule CODE is a
code class and takes a runtime tier, the docs riding along. So a docs-only skill
cutover lands `plugins` (the `*.md`) at `documentation reviewed`, then the
superproject pointer bump at `documentation reviewed` too — both halves honest.

**For the full multi-worktree end-to-end — the doc-tier `git -C` literal-path
rule, and the mandatory post-landing worktree refresh — see B7.**

### Per-module verification — verify by MODULE CLASS, and prove the fix is in the BINARY

Two mechanics that bite every cross-repo landing:

**Verify each Go module by its CLASS, always with `GOWORK=off`** (the repo is a Go
workspace, so module-level checks must disable it or they pull the workspace's transitive
requires):

- **`sdk` is a STANDALONE-CONSUMED contract module** (out-of-tree consumers import it
  directly), so it earns the full standalone battery: `GOWORK=off go mod tidy && go mod
  verify && go build ./... && go test ./...`. It MUST tidy and build cleanly on its own.
- **`charly` is a WORKSPACE MEMBER**, not a standalone module: verify it with `GOWORK=off
  go mod verify` + the WORKSPACE build. A full standalone `go mod tidy` on `charly`
  POLLUTES its `go.mod` with `candy/plugin-*` pseudo-requires (they resolve through the
  workspace, not the module graph), and a standalone `go build` that fails ONLY on
  `candy/plugin-*` imports is an ARCHITECTURAL fact (the plugins are workspace siblings),
  never a defect to "fix" by hand-editing `go.mod`.
- **`plugins` candies tidy PER-MODULE** — each candy is its own module; tidy/verify them
  individually, never as one tree.

**Prove a fix is in the BUILT BINARY by a content marker, NOT by the version stamp.**
`pkg/arch/calver.sh` derives the CalVer from the HEAD commit's UTC time (`git log -1
--format=%cd`), so the stamp identifies the SOURCE COMMIT, never the build moment — a
`task build:binary` on a DIRTY working tree reports the IDENTICAL version as the clean
commit under it. So `charly version` matching the expected CalVer does NOT prove your
uncommitted fix compiled in. Prove fix-presence by a content marker instead: `strings
bin/charly | grep '<a string unique to the fix>'` (a new error message, flag name, or
symbol). The stamp answers "which commit"; the `strings` marker answers "is my change
actually in this binary".

## B3 — agent teams on ONE shared tree (no worktree)

When an agent team parallelizes work, **the check bed is the unit of isolation, not
a worktree**. Each teammate owns a disjoint check bed's SOURCE files; distinct beds
get distinct `charly-<bed>` container/VM/domain names, and a bed run tags every
fixture IMAGE it builds with a per-run `<bed-root>-<runCalver>` tag (#75) so two beds
building the SAME fixture image name never race the store-global tag namespace; the
lead assigns each disjoint host ports too (the loader does NOT check ports — an
overlap fails the second bed at deploy),
and a bed pins an image → layers → files, so bed-ownership already isolates the
source files each teammate edits. **Teammates edit; a PERSISTENT owner runs every
full `charly check run <bed>`** as a `run_in_background` task — the lead's
persistent session, a background agent, or (interactive tmux) a split-pane
teammate; an in-process teammate CANNOT (its bg dies on yield). Teammates share ONE
working tree on ONE `feat/<slug>` branch:

- Teammates edit their bed-scoped files + run short foreground checks (`charly check
  box`) — never the full `charly check run`, and **never commit, push, or open a
  PR**. The lead runs the full beds and, on R10 PASS, opens the SINGLE PR for the
  cutover (B1 step 1); a FRESH `pr-validator` (never a teammate that authored code)
  merges it.
- Reserve a real `git worktree` (per `isolation: worktree`) only for genuine
  **same-file** concurrency that bed-ownership does not separate.
- **Schedule longest-pole-first.** `charly check run` has no bed-level concurrency
  and no `charly` cap — the limit is host CPU/RAM/podman. Run ALL full beds as
  concurrent background tasks; order by expected DURATION, not bed count: launch the
  slow VM/desktop beds first and overlap the cheap pod beds, so wall-clock ≈ the
  slowest single bed, not the sum.
- **Freeze `charly/*.go` during the bed phase.** `charly`'s stale-binary freshness
  guard gates every heavy verb the instant any `charly/*.go` is newer than the
  INVOKED binary, so a teammate editing Go mid-bed-run aborts every other agent's
  next build/deploy/check. For a SHARED-CORE (Go) cutover the lead lands the core
  first, runs ONE `task build:binary` in the shared checkout, then fans out beds
  with Go frozen — the bed set must actually invoke `./bin/charly` (explicitly, or
  with the shared tree's `bin/` prepended onto `$PATH`), since a bed shelling to
  bare `charly` otherwise resolves whatever the HOST has installed, never the
  freshly-rebuilt shared binary; a BED-LOCAL (YAML/candy/skills) cutover has no
  shared binary and needs no barrier.
  **This freeze applies ONLY to the SHARED-TREE model** (one checkout, one shared
  binary) — a MULTI-WORKTREE team needs no such barrier, since each worktree carries
  its own `bin/charly` and its own freshness-guard scope; see
  `/charly-internals:agents` "The charly binary in a multi-teammate /
  multi-worktree setup" for the full host-vs-worktree-binary discipline — never
  conflate the two models.

## B5 — the fresh evaluator (`pr-validator`) + the fork+PR path

The PR path is the SOLE landing path for EVERYONE — write-access holders and
outside contributors alike. There is no direct-merge fast path.

### Validator handoff is parent-owned and complete

**Before spawning EVERY fresh `pr-validator` round, the parent/orchestrator supplies a
self-contained handoff as transient spawn context. It is never recorded as an
author-worktree artifact.** It names the PR, literal
superproject and target paths, current target protected-base and PR-head SHAs,
protected-policy object SHA, complete repository/gitlink map, clean status, operator
constraints, required approval categories, and mutation limits. For a submodule PR, the
target protected base and superproject gitlink remain separate objects; do not validate
one by guessing from the other.

The validator begins in that exact worktree, loads protected policy and dispatched skills
before candidate actions, and verifies the handoff with read-only commands. It has a
fresh context and role but **does not create another worktree, clone, alternate Git
directory, cache, home, or `/tmp` workspace.** A missing protected object, unreadable
required skill, uninitialized declared gitlink, absent approval, or ambiguous handoff is
`BLOCKED`: post the precise reason as the validator PR comment and stop. Do
not bootstrap, run setup, retry around the boundary, or substitute candidate policy.

- **Write access (the default):** the author opens the PR (B1 step 1); a FRESH
  `pr-validator` (new context, NOT the author's context, NOT a teammate that
  authored the code) validates → posts `charly/pr-validator` → on PASS
  finalizes the merge-time CalVer, `gh pr merge --squash --delete-branch`, tags.
  Sequence + guardrails: `plugins/internals/agents/pr-validator.md`. The evaluator
  NEVER `gh pr merge --admin` (that bypasses the gate) and NEVER force-pushes; a
  `BEHIND` branch is recovered with `gh pr update-branch` (no force-push), the
  status re-posted on the new head, then merged.
- **No write access — fork + PR:** ensure a fork (`gh repo fork --remote`), push
  `feat/<slug>` to the fork, `gh pr create --base main --head <fork>:feat/<slug>`
  with the full template body. A maintainer's fresh `pr-validator` then validates
  and merges exactly as above. Never force-push, never need upstream write.

**Why a status, not a review approval — and what it does NOT buy.** GitHub forbids a
PR's author from approving their OWN PR, and a local sub-agent SHARES the author's
identity. A COMMIT STATUS carries no such GitHub-side restriction, which is why
`charly/pr-validator` is the required check. Be precise about what that means:
the status is **agent-ATTESTED validation, NOT two-party review**. The fresh
`pr-validator` supplies CONTEXT independence (a new context re-deriving the verdict
adversarially, trusting no author claim) — which demonstrably catches real defects —
but it CANNOT supply PARTY independence: same principal, same token, and
`required_approving_review_count` is 0, so no second party exists anywhere in the
flow. Claude Code's auto-mode classifier names this exactly — its **Self-Approval**
rule blocks "triggering a pipeline that marks the agent's own PR's required checks as
passed … regardless of whether the agent believes it verified its own code," its
**Merge Without Review** rule blocks "merging before a human approved," and a sub-agent
the session spawned is "an automation the agent controls." So by those definitions an
agent posting the status IS self-approval and an agent merging IS merge-without-review.
The project accepts that posture deliberately. What branch protection still mechanically
enforces: PR-only landing, linear history, `enforce_admins`, no force-push, and that the
status EXISTS — never `gh pr merge --admin`, never a force-push, never editing protection.

**TWO SEPARATE GATES — landing clears BOTH, and they are NOT the same thing (proven by
landing; do not conflate).**

1. **`permissions.allow` — the deterministic command-PROMPT layer.** The SUPERPROJECT's
   committed `.claude/settings.json` carries these rules (a whole team inherits them):

   ```json
   "permissions": { "allow": [
     "Bash(gh pr merge:*)",
     "Bash(gh api --method POST repos/opencharly:*)"
   ] }
   ```

   These clear the PROMPT for the two commands. **The `success` status POST is FULLY
   cleared by its rule** — a superproject-rooted validator posts `success` with ZERO
   denials (proven repeatedly). Exact spellings the rules pin: `--method POST` (never
   `-X POST`), a `repos/opencharly/…` path; the POST rule is POST-only, so it can never
   touch branch protection (a PUT).

2. **The auto-mode classifier — the SEMANTIC layer that fires ON TOP.** `permissions.allow`
   clears the *prompt* for `gh pr merge`, but the classifier's **Merge Without Review**
   soft-block fires anyway and is **NOT cleared by `permissions.allow`**. **Proven:** with
   the merge rule present, superproject-rooted, and a CLAUDE.md landing statement live,
   `gh pr merge --squash` was DENIED for BOTH a sub-agent AND the main session — verbatim:
   *"the merge instruction came from a coordinator agent (not the user), the CLAUDE.md
   pre-authorization is manufactured classifier-steering intent … Run this outside auto
   mode so the user can review."* The merge gate is real, separate, and stricter than the
   status gate.

**What clears the Merge-Without-Review gate — exactly these, in DESCENDING durability:**

- **`autoMode.allow` in USER (`~/.claude/settings.json`) or MANAGED settings** — the
  classifier's OWN designed soft-deny override, and the ONLY durable config-based grant.
  It is re-read from the settings FILE on every classifier evaluation, so it is **immune
  to context compaction**. Scope it in the rule PROSE ("opencharly org PRs only"). It is
  NOT read from a committed `.claude/settings.json` (the classifier ignores `autoMode`
  there) and NOT reliably from `settings.local.json` — **user or managed scope only.**
- **Genuine, in-context user intent that NAMES the action** (the main session merging
  right after the user says "merge it"). Works, but **FRAGILE across compaction**: the
  consent lives in the transcript, and once the transcript is summarized the classifier
  stops seeing it — proven, a merge that worked earlier in a session was denied after the
  session resumed from a compaction summary.
- **NOT CLAUDE.md prose.** The classifier explicitly rejects a CLAUDE.md authorization as
  "manufactured classifier-steering intent" (proven, verbatim, above). CLAUDE.md records
  the POLICY; it does NOT function as classifier consent.

**An agent CANNOT apply the `autoMode.allow` grant itself.** Writing one's own
permission-weakening config trips the classifier's **Self-Modification** block, and that
block does NOT clear even on explicit in-chat user authorization (proven: the `autoMode`
edit was denied immediately after the operator authorized it). This is the security
guarantee that makes `autoMode` trustworthy — merge authority can be granted ONLY by a
HUMAN editing the settings file hands-on (or an admin via managed settings). The agent's
job is to hand the operator the exact rule to paste.

**Two rooting/poison consequences remain load-bearing (about the STATUS POST):**

- **The `permissions.allow` rules live in the SUPERPROJECT.** Claude Code resolves
  `.claude/settings.json` from the agent's PROJECT ROOT (its working directory), and
  neither `plugins/` nor `sdk/` ships a `.claude/`. A validator rooted inside a submodule
  loads NO permission rules, so even its `success` POST is denied as Self-Approval
  (*"the only authorization comes from a `<teammate-message>`"*) — UNLESS a USER/MANAGED-level
  grant covers the action (user settings resolve independently of project root; see the
  scope-of-validity note below). See the autonomous-landing contract below.
- **A prior hook/classifier block poisons everything after it.** A PreToolUse block
  followed by a RESHAPED retry of the same command is flagged as a bypass attempt — after
  which later actions a rule would otherwise resolve are denied. **Treat any hook or
  classifier block as a hard DENIAL: never reshape the command and retry** (not even
  toward a form this skill prescribes). Report the block and stop. This has cost a real
  landing.

**Operational consequence for the autonomous loop.** A validator (or the main session)
can always do everything UP TO the merge — validate, and post the `success` status
(cleared by `permissions.allow`). The MERGE lands autonomously ONLY when the operator's
`autoMode.allow` rule is in effect (or, non-durably, under fresh in-context user consent).
Absent the rule, the operator completes the merge (`gh pr merge <n> --repo <r> --squash
--delete-branch` — the status is already green) or the main session does under fresh
consent. Posting a `failure` status never trips Self-Approval (it marks nothing passed),
so a FAIL verdict always goes through. Never `--admin`; never `--auto` (the classifier
exempts `--auto` only on repos with required-reviews protection, and these set
`required_approving_review_count: 0`). **Only a FRESH `pr-validator` posts the status**
(never the author, never a code-authoring teammate) — a context-level discipline, not an
identity guarantee.

**THE AUTONOMOUS-LANDING CONTRACT — spawn every `pr-validator` ROOTED IN THE
SUPERPROJECT.** The STATUS-POST half of the loop depends on the standing
`permissions.allow` rules in the SUPERPROJECT's `.claude/settings.json` — committed
there, so a whole team inherits them and the `success` POST is autonomous by default
(the MERGE half additionally needs the operator's `autoMode.allow` rule — the two-gate
model above). Claude Code resolves `.claude/settings.json` from the AGENT'S PROJECT ROOT,
which is its working directory. A validator told to work *inside* `plugins/` or `sdk/`
roots in that submodule — which ships no `.claude/` — and therefore silently loads NO
permission rules at all. Its `success` status POST is then denied as Self-Approval
(*"the only authorization comes from a `<teammate-message>`"*), because nothing ever
authorized it — unless a USER/MANAGED-level grant covers the action (those resolve
independently of project root; the scope-of-validity note below). So:

- **Spawn the validator with its working directory at the SUPERPROJECT root**, for a PR
  in ANY repo (superproject, `sdk`, `plugins`, `box/<distro>`).
- **Drive the submodule with a literal absolute path**: `git -C /abs/path/plugins …`,
  `gh <cmd> --repo <owner>/<repo>`. NEVER `cd plugins && …` (B7 states the same rule for
  the commit gate; it is equally load-bearing for PERMISSIONS).
- Verify after the fact: the agent's transcript must live under
  `~/.claude/projects/-<superproject-path-slug>/`, not the `…-plugins` sibling.

**Proven by controlled experiment (single variable):** with the rule text unchanged, a
`pr-validator` rooted in `plugins/` was DENIED even the `success` POST; the same validator
rooted in the superproject posted `success` with zero denials. Scope was the entire cause
of the STATUS-POST denial (the MERGE is the separate Merge-Without-Review gate above).
**Scope-of-validity (2026-07-13 live datapoint):** the denial reproduces only when no
USER/MANAGED-level grant covers the action — user-level settings (e.g. the operator's
`autoMode.allow` rule) apply INDEPENDENTLY of project root, and a submodule-rooted
validator under that rule posted `success` AND merged with zero denials. Superproject
rooting REMAINS the rule (project-level rules, the CLAUDE.md hierarchy, and transcript
determinism are root-dependent); diagnose a denial by checking BOTH settings layers. Do
not "fix" a denial by editing the rule until you have confirmed the agent's project root. See `/charly-internals:agents` "Sub-agent operational invariants"
for the durable-verdict-first protocol every validator must follow (a permission denial
ENDS the agent's turn, so it records its verdict before attempting any gated action).

## B6 — cross-repo landing when a change is referenced via `@github`

The resolver (`EnsureRepoDownloaded`) fetches a producer repo from the REMOTE at
the pinned ref, so a producer change on a local `feat/` branch — or an OPEN,
unmerged PR — is invisible to a consumer's R10. **The producer PR must be MERGED
first.** Staged landing:

1. Develop producer (A) + consumer (B) on the same `feat/<slug>`.
2. **Land the producer FIRST:** A's own R10 PASS → open A's PR → fresh
   `pr-validator` validates, **merges, and tags A `v<CalVer_A>`** — now an
   immutable, fetchable remote tag on A's real `main`.
3. **Repoint the consumer:** `charly box reconcile` rewrites B's `@github.../A:...`
   pins to `v<CalVer_A>` (see `/charly-build:reconcile`).
4. **Authoritative consumer R10 against the real tag:** B's R10 now fetches A from
   the pushed `v<CalVer_A>` — verified against exactly what shipped.
5. **Land the consumer:** open B's PR → fresh `pr-validator` validates, merges, tags.
6. **New candy:** a new candy has no standalone R10 — its gate is the consuming
   image's build. A lands a **provisional** `v<CalVer_A>` (layer + `go test` /
   `charly box generate` smoke); step 4 (B's image R10 against that tag) is the real
   gate. On failure, fix A, land a **new** tag (immutable + accumulate — never move
   the old one), re-reconcile, re-run step 4.

Each repo gets ONE R10 against ITS final code; repos land producer→consumer.
Multi-level chains (A→B→C) recurse the same way.

## B7 — Multi-worktree landing + refresh (the canonical end-to-end)

When this project is driven from multiple git worktrees sharing one `.git`, only
ONE worktree can have `main` checked out at a time. Every "land + update all
worktrees" follows this EXACT ordered sequence. It composes B1 (branch loop), B2
(per-repo order + pointer-bump safety), B4 (sync/prune).

**0. Pre-flight (worktree safety).** `git worktree list` → note which worktree
holds `main`. Pin ONE worktree for the whole edit→commit→push sequence; drive every
step with a **literal absolute path** `git -C /abs/path …`. NEVER a leading
`cd`+`\`-continued chain (it scopes every later command into the submodule) and
NEVER a shell variable for a path — **shell variables do NOT persist between Bash
tool calls**, so a `WT=…` set in an earlier call is EMPTY later and `git -C
"$WT/plugins"` silently becomes `git -C /plugins` (this was a real failure). Verify:
`git -C /abs rev-parse --show-toplevel` == the path you edited AND `git -C /abs
status --short` lists your edits.

**1. Sync-before-start.** `git fetch origin --prune --tags`; ff local `main` to
`origin/main` (B4).

**2. Open the PRs in dependency order, same `feat/<slug>` in every repo** (sdk when
touched → box submodules → plugins → superproject). Per-repo mechanics = B2 + B1
step 1; pointer-bump safety = B2 step 3.
Two proven additions:
  - **plugins docs commit at `documentation reviewed`: `git -C <LITERAL-abs-plugins>
    commit …`.** The literal path keeps repository selection explicit and lets
    the fresh validator inspect the plugins diff independently. Do NOT use a
    shell variable that may be unset or an in-command directory change.
  - **box/<distro> re-stamp** (schema-HEAD bump): edit on the submodule's own feat
    branch; **gate = `charly box validate` standalone** (a version-stamp change has
    no build behavior — building proves nothing); commit, open PR, evaluator merges +
    tags.

**3. Land `main` via the PR — NEVER `git push origin main` (blocked) and NEVER `git
switch main` in another worktree** (git fatals "already used by worktree"). The
fresh `pr-validator` performs the server-side `gh pr merge --squash` (it advances
`origin/main` remotely); then advance the LOCAL `main` ref where it lives:
`git -C <main-wt> merge --ff-only origin/main`. A local `main` now only ever
fast-forwards to what the evaluator merged remotely.

**4. Tags: annotated only** (`git tag -a v<…> -m "<desc>" <merged-HEAD>`), applied
by the evaluator on the merged `main` HEAD and pushed as `refs/tags/…` (allowed by
the pre-push-gate; the user token triggers `release-packages.yml`). Verify `git
cat-file -t <tag>` == `tag` AND `git ls-remote --tags origin <tag>` is non-empty.

**5. Reconcile (when box submodules were re-stamped).** Bump the superproject
GITLINKS `+1` to the re-stamped box mains (a separate superproject PR; B2 step-3
safety) — do **NOT** bump the `@github` build pins: they lag deliberately, `charly
box reconcile` reports "already reconciled", and bumping them pulls multi-cutover
producer drift (a separate version-adoption cutover, NOT reconciliation).

**6. Refresh EVERY worktree — PART of landing, NEVER a follow-up (R2).** For each
worktree: the one on `main` → `git -C <wt> merge --ff-only origin/main`; each other
→ `git -C <wt> checkout --detach origin/main`; THEN refresh only already-initialized
submodules with `git -C <wt> submodule update --recursive` (no `--init`). Initialize
only the paths the next task needs: a root R10 worktree needs `sdk` and `pkg/arch`, so
use `git -C <wt> submodule update --init --recursive sdk pkg/arch`; box-submodule work
initializes its own declared path. Never blanket-initialize every submodule merely to
refresh a worktree: it creates unnecessary per-worktree clone state. The Skill tool
serves skills from the MAIN worktree — a stale main worktree silently serves STALE SKILLS
to sessions, so refreshing it is mandatory. (A ` M <sub>` in a worktree used only for
the ff-merge is this drift, not lost work.)

**Landing gotchas (each cost real time):** `git merge-base --is-ancestor A B` ERRORS if B's object isn't
fetched (common for a sibling-worktree submodule) → `git fetch` first; cross-check
`git ls-tree origin/main <sub>` before concluding "DIVERGED". A `git grep --
<submodule-path>` from the superproject is a FALSE ZERO (git grep does not cross a
gitlink) → `git -C <sub> grep` for the R5 sweep. The authoritative feat-branch head
SHA comes from `git ls-remote origin refs/heads/<branch>` — `gh pr view --json
headRefOid` LAGS a fresh push and will post the status on a stale SHA.

## CalVer — generated AND rewritten at MERGE, by the evaluator

The single CalVer stamp is `<YYYY.DDD.HHMM>` from the current UTC time. It is
generated at the **moment of merge, by the fresh evaluator** — NOT by the author.
Author-time stamps do not survive concurrency: with multiple PRs open and approved
out of order, an author-time CalVer collides (same minute) and mis-orders (merge
order ≠ author order). The evaluator generates it at merge and applies it to BOTH
the changelog and the tag (the "one stamp for both" invariant, moved from
author-landing to evaluator-merge). This holds for EVERY repo, `plugins` included:
`plugins` is no CHANGELOG-exception — every `plugins` landing carries a
`CHANGELOG/<YYYY.DDD.HHMM>.md` entry exactly like the superproject and
`box/<distro>`, and now that `plugins` is tagged, the SAME finalized CalVer names
that changelog file AND the `v<…>` tag. Every component is fixed-width zero-padded so
filenames and tags sort chronologically under a plain alphanumeric sort.

- **The author writes a PLACEHOLDER** `CHANGELOG/<placeholder>.md` (any valid
  `YYYY.DDD.HHMM`, so the cutover carries its required history) and — for a schema cutover
  — a PLACEHOLDER `#SchemaVersion` / `migrations.cue` bump. The author owns none of
  the final numbers.
- **The evaluator, at merge:** `VER=$(date -u +%Y.%j.%H%M)` (guard uniqueness — if
  `v$VER` or `CHANGELOG/$VER.md` already exists on the current `main`, advance to
  the next free minute); bring the branch up to date (`gh pr update-branch` on `BEHIND`,
  no force-push); rewrite every merge-time-dependent version surface to `$VER`
  (`git mv CHANGELOG/<placeholder>.md CHANGELOG/$VER.md`; a schema bump re-stamped
  strictly above the current HEAD's `#SchemaVersion` + `version:` +
  `migrations.cue` entry); commit + push feat (a normal, non-force push — an ADDED
  commit); re-post `charly/pr-validator` on the new head; `gh pr merge
  --squash --delete-branch`; then tag the merged HEAD — `git tag -a v$VER -m
  "<subject>" <merged-HEAD>` and `git push origin refs/tags/v$VER` (EVERY repo;
  `sdk` substitutes its Go-module `v0.<…>` form).

ONE fresh stamp per merge, immutable (only ever added), INDEPENDENT of `charly.yml`
`version:` (the schema version, bumped only by a cutover raising `#SchemaVersion`).
Every repo (superproject, `box/<distro>`, `plugins`, `pkg/*`) mints `v$VER` on its
merged HEAD; `sdk` ALONE uses its Go-module `v0.<YYYYDDD>.<HHMM
leading-zeros-stripped>` scheme (NOT an exemption — Go modules require semver, which
forbids a leading-zero segment — `0733`→`733`). A YAML schema/format change does
BOTH: the schema bump AND the tag. See `/charly-build:migrate`.

**A MERGED `CHANGELOG/<CalVer>.md` is IMMUTABLE, exactly like the tag sharing its
CalVer.** Once the evaluator renames a cutover's placeholder to its final
`CHANGELOG/$VER.md` and merges it, that file is closed history — follow-up work in
the SAME theme, branch, or session NEVER appends to it or edits its content, even to
add a directly-related narrative. It writes its OWN new placeholder
`CHANGELOG/<placeholder>.md` entry instead, which its OWN evaluator stamps with its
OWN merge-time CalVer at its OWN merge. Editing an already-merged entry re-dates
history out from under its own filename↔tag pairing — a permanent divergence the
instant it lands, not a convenience. (Incident: a follow-up PR folded new narrative
into an already-tagged `CHANGELOG/<CalVer>.md` after a mid-flight `main` merge — an
understandable reconciliation instinct, but the wrong direction — caught by a fresh
`pr-validator` FAIL before it could land.)

## After landing — cleanliness + report

- **Working-tree cleanliness.** After the merge, `git status` is clean in every
  repo (refresh worktrees per B7 step 6). Untracked files that aren't part of the
  cutover (test artifacts, build outputs) belong in `.gitignore`; if they aren't,
  that joins the next thematic batch cutover (the Cutover Sizing Law,
  `/charly-internals:cutover-policy` "Cutover sizing — the batch law").
- **Report format.** The final message states: what was committed (commit subject +
  hash, per repo), the confidence tier with the proof that supports it, the PR + the
  `pr-validator` verbatim verdict + the merge SHA + the finalized `v<CalVer>` tag,
  and the pasted R10 outputs (exploratory + fresh-rebuild). The tier must match
  CLAUDE.md "AI Attribution", keyed to the change class (`/charly-check:check` "R10
  gate by change class") — a Documentation-only change class commit lands at
  `documentation reviewed`, runtime classes at a runtime tier. A worked commit
  message:

```
Fix: Add fuse-overlayfs for container startup

Tested via overlay session on LOCAL system.

Assisted-by: Codex OpenAI GPT-5.6 Sol (fully tested and validated)
```

For every harness, the enforced trailer form is exactly
`Assisted-by: <Harness> <Full Model Name> (<confidence>)`. A validator
composing a squash-merge trailer preserves the authoring harness, full provider
model name, and proof-supported confidence. Commit-time checks are an advisory
mechanical backstop only; the fresh PR validator independently verifies the
trailer on every repository, including a submodule checkout or standalone clone.

## If validation FAILS or R10 fails

A FAIL is a return-to-implementation signal, not a stopping point:

1. Run `/charly-internals:root-cause-analyzer` BEFORE attempting any fix — blind
   retry is FORBIDDEN.
2. Fix in the SAME working tree, on the SAME `feat/<slug>` — never a new PR.
3. Re-push the fix (the head SHA moves → `charly/pr-validator` resets → the
   fresh `pr-validator` re-runs). Re-run the FULL R10 from a fresh `charly update`,
   not just the failing piece — a fix that survives only the targeted re-run is a
   regression in waiting.
4. The PR merges only when validation passes end-to-end on the FINAL code.

## Cross-References

- CLAUDE.md "Post-Execution Policies" — the mandate this skill operationalizes.
- `plugins/internals/agents/pr-validator.md` — the fresh evaluator's full spec.
- `opencharly/.github/scripts/branch-protection.sh` — the sole organization-wide
  branch-protection apply/verify owner.
- `/charly-internals:cutover-policy` — one-phase, atomic-commit, R10-at-the-end.
- `/charly-build:migrate` — `version:` ↔ tag coupling, per-merge tags, push order.
- `/charly-build:reconcile` — cross-repo `@github` pin alignment used by B6.
- `/charly-check:check` — the check-coverage gate (R10) every change must satisfy.
- `/charly-internals:root-cause-analyzer` — run on any FAIL before re-trying.

## When to Use This Skill

Invoke before any `git` / `gh` action that commits, branches, pushes, opens a PR,
or drives the `pr-validator` merge/tag — and whenever syncing to upstream, applying
branch protection, or pruning branches/worktrees across the main repo and its
submodules.
