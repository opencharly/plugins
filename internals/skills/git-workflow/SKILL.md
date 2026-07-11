---
name: git-workflow
description: |
  Use when committing, branching, pushing, opening PRs, or landing a change with
  gh — the feat/-branch, R10-gated, PR-ONLY, agent-validated, never-force-push
  landing across the main repo + the sdk/plugins submodules + box/<distro>
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
  merge. GitHub branch protection requires the `charly/claude-validation` status
  (posted by the fresh `pr-validator`) + a PR + linear history + `enforce_admins`;
  the `pre-push-gate` blocks every main-destination push locally. Apply/verify with
  `scripts/apply-branch-protection.sh {apply|verify}`.
- **NEVER force-push.** No `git push --force`, no `--force-with-lease`, on ANY
  branch (`feat/` included) in ANY repo, ever. The flow never needs one: `feat/`
  advances only by ADDING commits (the author's change, any review-round fix commits,
  then the evaluator's merge-time version stamp) and the squash-merge collapses them;
  a stale `feat/` is brought up to date with `gh pr update-branch` (a merge, NOT a
  rebase-force); tags are add-only. `git commit --amend` on a PUSHED branch is
  therefore forbidden too — it diverges the branch and can only be published by a
  force-push. Amend only before the first push.
- **R10-gated.** R10 PASS authorizes OPENING the PR (with pasted evidence). The
  MERGE is gated on the fresh `pr-validator`'s green `charly/claude-validation`
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
- **Check-coverage.** R10 does not pass unless the change ships the test coverage
  that PROVES its functionality (`check:` checks for new/changed layers & images,
  Go tests for `charly` code) AND the live run exercised it. A change whose new
  functionality has no test that would FAIL without it is not landable.
- **Tags only on `charly.yml` repos** — plus the sdk contract repo, which tags
  under its own Go-module scheme `v0.<YYYYDDD>.<HHMM with ALL leading zeros
  stripped>` (B2 step 0; semver forbids a leading-zero segment — `0733`→`733`).
  `plugins` and `pkg/*` are tag-exempt.

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
git commit -m "<conventional commit> ...  Assisted-by: Claude (<tier>)"
git push origin feat/<slug>                       # feat push — allowed by the gate
gh pr create --base main --head feat/<slug> \     # fill the PR template completely (single org source: opencharly/.github/.github/PULL_REQUEST_TEMPLATE.md — no per-repo copy)
  --title "<subject>" \
  --body "<summary + change class + pasted R10 evidence + tier + R0–R10 checklist>"
# STOP. Do NOT merge your own PR. Hand off to a FRESH pr-validator (Step 2).
```

**Step 2 — Fresh evaluator** (`plugins/internals/agents/pr-validator.md`, spawned
with NEW context): it independently re-validates the PR vs R0–R10 + the relevant
skills, posts `charly/claude-validation` on the head SHA, and ONLY on PASS
generates the merge-time CalVer, rewrites the version surfaces on `feat/` (the
`CHANGELOG` rename + any schema bump), re-posts the status on the new head,
`gh pr merge --squash --delete-branch`, and tags. The author pastes the evaluator's
verbatim verdict + what it merged/tagged (paste-proof survives delegation). On
FAIL the PR stays OPEN and is **UPDATED IN PLACE** → the author R1-RCAs, fixes in the
same tree, APPENDS a fix commit, and pushes it fast-forward (status resets) → the
evaluator re-runs. **Never close a PR and open a replacement to carry a fix.**

Because the merge is a SQUASH and `main` is protected linear, `main` gains exactly
ONE commit per cutover — the author's change, any review-round fix commits, and the
version stamp, folded together.

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
2. `plugins` — PR → evaluator merges (**no tag**, no `charly.yml`);
3. the superproject — stage the now-MERGED submodule pointers (a touched sdk: the
   `sdk` gitlink bump PLUS the `charly/go.mod` require version — in-tree resolution
   rides `replace github.com/opencharly/sdk => ../sdk`, so the require version
   matters only for out-of-tree consumers, but it is staged here) → PR → evaluator
   merges + tags `main`.

A producer PR must be **merged** (not merely green) before the consumer's pointer
bump — the superproject pointer must reference a commit that is on the submodule's
real `main`, which only the merge produces.

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
lands at `documentation reviewed`: `pre-commit-gate.sh` recurses into the
submodule's own `old..new` diff to certify it (objects must be present locally; a
bump it cannot certify is rejected). A bump that integrates submodule CODE is a
code class and takes a runtime tier, the docs riding along. So a docs-only skill
cutover lands `plugins` (the `*.md`) at `documentation reviewed`, then the
superproject pointer bump at `documentation reviewed` too — both halves honest.

**For the full multi-worktree end-to-end — the doc-tier `git -C` literal-path
rule, and the mandatory post-landing worktree refresh — see B7.**

## B3 — agent teams on ONE shared tree (no worktree)

When an agent team parallelizes work, **the check bed is the unit of isolation, not
a worktree**. Each teammate owns a disjoint check bed's SOURCE files; distinct beds
get distinct container/VM/image names; the lead assigns each disjoint host ports
too (the loader does NOT check ports — an overlap fails the second bed at deploy),
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
  guard gates every heavy verb the instant any `charly/*.go` is newer than
  `/usr/bin/charly`, so a teammate editing Go mid-bed-run aborts every other agent's
  next build/deploy/check. For a SHARED-CORE (Go) cutover the lead lands the core
  first, runs ONE `task build:charly`, then fans out beds with Go frozen; a
  BED-LOCAL (YAML/candy/skills) cutover has no shared binary and needs no barrier.

## B5 — the fresh evaluator (`pr-validator`) + the fork+PR path

The PR path is the SOLE landing path for EVERYONE — write-access holders and
outside contributors alike. There is no direct-merge fast path.

- **Write access (the default):** the author opens the PR (B1 step 1); a FRESH
  `pr-validator` (new context, NOT the author's context, NOT a teammate that
  authored the code) validates → posts `charly/claude-validation` → on PASS
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
`charly/claude-validation` is the required check. Be precise about what that means:
the status is **agent-ATTESTED validation, NOT two-party review**. The fresh
`pr-validator` supplies CONTEXT independence (a new context re-deriving the verdict
adversarially, trusting no author claim) — which demonstrably catches real defects —
but it CANNOT supply PARTY independence: same principal, same token, and
`required_approving_review_count` is 0, so no second party exists anywhere in the
flow. Claude Code's auto-mode classifier names this exactly — its **Self-Approval**
rule blocks "triggering a pipeline that marks the agent's own PR's required checks as
passed … regardless of whether the agent believes it verified its own code," and a
sub-agent the session spawned is "an automation the agent controls." So an agent
posting this status IS self-approval by that definition. The project accepts that
posture deliberately, with the operator's standing authorization recorded in
`permissions.allow` (next paragraph). What branch protection still mechanically enforces:
PR-only landing, linear history, `enforce_admins`, no force-push, and that the status
EXISTS — never `gh pr merge --admin`, never a force-push, never editing protection.

**Where the merge + status-post authority comes from — `permissions.allow`, and nothing
else.** The SUPERPROJECT's `.claude/settings.json` carries deterministic permission
RULES in `Tool(pattern)` syntax, and those two rules ARE the standing authorization:

```json
"permissions": { "allow": [
  "Bash(gh pr merge:*)",
  "Bash(gh api --method POST repos/opencharly:*)"
] }
```

A matching rule resolves the action for a SUB-AGENT exactly as for the interactive main
session — verified by landing: a fresh, superproject-rooted `pr-validator` posts `success`
and merges with **zero denials**, on a host whose settings carry **no `autoMode` key at
all**. Note the exact spellings the rules pin: `--method POST` (never `-X POST`), and a
`repos/opencharly/…` path. The POST rule is POST-only, so it can never touch branch
protection (a PUT).

Two consequences follow, and both are load-bearing:

- **The rules live in the SUPERPROJECT.** Claude Code resolves `.claude/settings.json`
  from the agent's PROJECT ROOT, which is its working directory, and neither `plugins/`
  nor `sdk/` ships a `.claude/` of its own. A validator rooted inside a submodule loads
  NO permission rules, and its `success` POST is denied as Self-Approval (*"the only
  authorization comes from a `<teammate-message>`"*). See the autonomous-landing
  contract below.
- **A prior hook block poisons everything after it.** The auto-mode classifier evaluates
  sub-agent actions, and a PreToolUse block followed by a RESHAPED retry of the same
  command is flagged as a bypass attempt — after which it denies later actions a
  `permissions.allow` rule would otherwise have resolved. **Treat any hook or classifier
  block as a DENIAL: never reshape the command and retry** (not even toward a form this
  skill prescribes). Report the block and stop. This has cost a real landing.

Posting a `failure` status never trips Self-Approval — it marks nothing passed — so a
FAIL verdict always goes through; only `success` is gated. Never reach for the
`gh pr merge --auto` carve-out: the classifier exempts `--auto` only on a repo **with
required-reviews branch protection** ("`--auto` queues until reviews+checks pass; the
gate is server-enforced"), and these repos set `required_approving_review_count: 0`, so
that precondition is unmet and the exemption does NOT apply here. The flow uses
`--squash` and never `--auto`. The load-bearing discipline is unchanged: **only a FRESH
`pr-validator` (never the PR's author, never a teammate that authored the code) posts
the status** — that is a context-level discipline, not an identity guarantee.

**THE AUTONOMOUS-LANDING CONTRACT — spawn every `pr-validator` ROOTED IN THE
SUPERPROJECT.** The autonomous loop depends on the standing `permissions.allow` rules in
the SUPERPROJECT's `.claude/settings.json` — committed there, so a whole team inherits
them and the loop is autonomous by default. Claude Code resolves `.claude/settings.json`
from the AGENT'S PROJECT ROOT, which is its working directory. A validator told to work
*inside* `plugins/` or `sdk/` roots in that submodule — which ships no `.claude/` — and
therefore silently loads NO permission rules at all. Its `success` status POST is then
denied as Self-Approval (*"the only authorization comes from a `<teammate-message>`"*),
because nothing ever authorized it. So:

- **Spawn the validator with its working directory at the SUPERPROJECT root**, for a PR
  in ANY repo (superproject, `sdk`, `plugins`, `box/<distro>`).
- **Drive the submodule with a literal absolute path**: `git -C /abs/path/plugins …`,
  `gh <cmd> --repo <owner>/<repo>`. NEVER `cd plugins && …` (B7 states the same rule for
  the commit gate; it is equally load-bearing for PERMISSIONS).
- Verify after the fact: the agent's transcript must live under
  `~/.claude/projects/-<superproject-path-slug>/`, not the `…-plugins` sibling.

**Proven by controlled experiment (single variable):** with the rule text unchanged, a
`pr-validator` rooted in `plugins/` was DENIED the `success` POST; the same validator
rooted in the superproject posted `success` and merged with zero denials. Scope was the
entire cause. Do not "fix" a denial by editing the rule until you have confirmed the
agent's project root. See `/charly-internals:agents` "Sub-agent operational invariants"
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
    commit …`.** RDD-proven on the live gate: a literal `-C` scopes
    `pre-commit-gate.sh` to the plugins all-docs index in ONE shot (it passes even
    while the superproject has non-doc code staged, and recurses the submodule's
    `old..new` diff). Do NOT use a `$var` (may be unset → `git diff --cached --raw
    failed`); do NOT use `cd plugins && git commit` (the gate fires BEFORE the
    in-command `cd`, so it inspects the SUPERPROJECT index and blocks on staged
    code). The literal `-C` removes the old "empty the other index first" dance.
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
→ `git -C <wt> checkout --detach origin/main`; THEN `git -C <wt> submodule update
--init --recursive`. The Skill tool serves skills from the MAIN worktree — a stale
main worktree silently serves STALE SKILLS to sessions, so refreshing it is
mandatory. (A ` M <sub>` in a worktree used only for the ff-merge is this drift, not
lost work.)

**Landing gotchas (each cost real time):** the **PreToolUse pre-commit-gate fires
ONCE per Bash call, BEFORE the command runs** → a `git reset && git commit` in ONE
call fails (the reset hasn't happened yet); split into separate Bash calls. `task
build:charly` dirties `pkg/arch/PKGBUILD` (makepkg `pkgver()`) → `git -C <pkg/arch>
restore PKGBUILD`. `git merge-base --is-ancestor A B` ERRORS if B's object isn't
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
author-landing to evaluator-merge). Every component is fixed-width zero-padded so
filenames and tags sort chronologically under a plain alphanumeric sort.

- **The author writes a PLACEHOLDER** `CHANGELOG/<placeholder>.md` (any valid
  `YYYY.DDD.HHMM`, only to satisfy `pre-commit-gate.sh`) and — for a schema cutover
  — a PLACEHOLDER `#SchemaVersion` / `migrations.cue` bump. The author owns none of
  the final numbers.
- **The evaluator, at merge:** `VER=$(date -u +%Y.%j.%H%M)` (guard uniqueness — if
  `v$VER` or `CHANGELOG/$VER.md` already exists on the current `main`, advance to
  the next free minute); bring the branch up to date (`gh pr update-branch` on `BEHIND`,
  no force-push); rewrite every merge-time-dependent version surface to `$VER`
  (`git mv CHANGELOG/<placeholder>.md CHANGELOG/$VER.md`; a schema bump re-stamped
  strictly above the current HEAD's `#SchemaVersion` + `version:` +
  `migrations.cue` entry); commit + push feat (a normal, non-force push — an ADDED
  commit); re-post `charly/claude-validation` on the new head; `gh pr merge
  --squash --delete-branch`; then, taggable repos only, `git tag -a v$VER -m
  "<subject>" <merged-HEAD>` and `git push origin refs/tags/v$VER`.

ONE fresh stamp per merge, immutable (only ever added), INDEPENDENT of `charly.yml`
`version:` (the schema version, bumped only by a cutover raising `#SchemaVersion`).
Taggable repos (superproject, `box/<distro>`) mint `v$VER`; `sdk` uses its
Go-module `v0.<YYYYDDD>.<HHMM leading-zeros-stripped>` scheme (semver forbids a
leading-zero segment — `0733`→`733`); `plugins`/`pkg-*` stay tag-exempt (changelog
file only). A YAML schema/format change does BOTH: the schema bump AND the tag. See
`/charly-build:migrate`.

## After landing — cleanliness + report

- **Working-tree cleanliness.** After the merge, `git status` is clean in every
  repo (refresh worktrees per B7 step 6). Untracked files that aren't part of the
  cutover (test artifacts, build outputs) belong in `.gitignore`; if they aren't,
  that's its own immediate-next cutover.
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

Assisted-by: Claude (fully tested and validated)
```

## If validation FAILS or R10 fails

A FAIL is a return-to-implementation signal, not a stopping point:

1. Run `/charly-internals:root-cause-analyzer` BEFORE attempting any fix — blind
   retry is FORBIDDEN.
2. Fix in the SAME working tree, on the SAME `feat/<slug>` — never a new PR.
3. Re-push the fix (the head SHA moves → `charly/claude-validation` resets → the
   fresh `pr-validator` re-runs). Re-run the FULL R10 from a fresh `charly update`,
   not just the failing piece — a fix that survives only the targeted re-run is a
   regression in waiting.
4. The PR merges only when validation passes end-to-end on the FINAL code.

## Cross-References

- CLAUDE.md "Post-Execution Policies" — the mandate this skill operationalizes.
- `plugins/internals/agents/pr-validator.md` — the fresh evaluator's full spec.
- `scripts/apply-branch-protection.sh` — apply/verify the branch protection.
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
