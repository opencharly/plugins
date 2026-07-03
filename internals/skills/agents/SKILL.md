---
name: agents
description: |
  Claude Code multi-agent support in OpenCharly — sub-agents, dynamic workflows, and agent teams, and how each drives the existing `charly check` disposable beds to test and verify. MUST be invoked before authoring or invoking an charly sub-agent / dynamic workflow / agent team, wiring agent-lifecycle hooks, or asking "which primitive should drive the R10 beds?".
---

# Agents, Workflows & Teams

OpenCharly is built to be driven from Claude Code's multi-agent primitives.
This skill is the authoritative reference for the three primitives, the charly
agent roster, the shipped workflows, the bed-scoped parallel-testing model for
teams, and the one rule that binds them all: **a bed run is R10-class — the
commit is gated on a full final-code bed test (pasted), but beds run freely
throughout to verify** (CLAUDE.md "Hard Cutover by Default").

## The three primitives — when to use which

| | Sub-agent | Dynamic workflow | Agent team |
|---|---|---|---|
| What it is | A worker Claude spawns (Agent tool / @-mention) | A JS script the runtime executes | Multiple full Claude sessions: a lead + teammates |
| Holds the plan | Claude, turn by turn | The script | The lead + a shared task list |
| Intermediate results | Claude's context | Script variables | Each teammate's own context |
| Scale | a few per turn | dozens–hundreds of agents/run | 3–5 teammates |
| Lives in | `plugins/internals/agents/*.md` (or `.claude/agents/`) | `.claude/workflows/*.js` (run `/<name>`) | runtime only — `~/.claude/teams/`, NOT pre-authored |
| Reads CLAUDE.md | yes (full hierarchy, except Explore/Plan) | each `agent()` does | yes (each teammate) |

- **Sub-agent** — isolate a verbose side task (run a bed, probe a deploy) and
  get back a verdict; the noisy output stays out of the main context.
- **Dynamic workflow** — codify a repeatable fan-out (run every bed; audit
  every deploy config) as a script you can rerun. Triggered by the word
  `workflow` in a prompt, by `/effort ultracode`, or by a saved `/<name>`.
- **Agent team** — parallel *exploration/review* where teammates challenge
  each other (competing-hypotheses triage of an check failure). Experimental;
  opt-in only (see "Agent teams" below).

**Preference (default): agents over background tasks — everything that CAN run as
an agent SHOULD run as an agent.** Prefer an addressable, operator-visible
**sub-agent** or **agent-team teammate** over an opaque background **dynamic
workflow**. **Team agents are the DEFAULT for parallel work** — the operator
watches and messages them live, which is exactly the visibility/control a
background workflow hides. Reach for a background `Workflow` only as a LAST
RESORT, when deterministic scripted control flow (loops / conditionals / large
fan-out) genuinely cannot be expressed as a team — and even then it surfaces its
work as agents and stays bed-scoped (see "Implementation workflows are bed-scoped
too"). Operator-facing agents beat opaque background tasks every time. **The one
exception is long-running work that outlives a single turn** (a VM/emulator check
bed): no agent can reliably hold it — a sub-agent returns synchronously (its
background children die on return) and a teammate is torn down on idle — so it
runs as a harness-tracked background task owned by the persistent session, driven
by the completion notification (see "Handling a long-running bed — by mechanism"
under the binding rule). "Prefer agents" governs BOUNDED work.

## The charly agent roster (`plugins/internals/agents/`)

**Executors** — they RUN `charly check` and return verbatim proof:

- **`check-bed-runner`** — runs `charly check run <bed>` ONE-SHOT (the full R10
  sequence: build → check image → deploy → check live → fresh `charly update` →
  teardown) on a disposable check bed; returns per-step status, exit code
  (0 pass / 1 infra / 2 checks-failed), and the failing-step log tail. The R10
  acceptance discipline. A **persistent owner runs every full bed as a
  `run_in_background` task** (main session / background agent / split-pane
  teammate — see "Bed-scoped" below; an in-process teammate CANNOT, its bg dies
  on yield) and pastes the verbatim verdict; teammates do bed-local edits + short
  foreground checks (`charly check box`), never the full run. There is no
  duration/600s carve-out — the 600s is a Bash FOREGROUND cap, irrelevant to a
  backgrounded bed.
- **`deploy-verifier`** — read-mostly: `charly check box` / `charly check live` /
  `charly status` against an image or a running deploy (the charly repo's images OR a
  user's own deploy config). Answers "does this deploy config work?" without
  mutating anything.

**Enforcers** — they GATE claims (dev discipline):

- **`root-cause-analyzer`** — R1 mandatory invocation on any failure/anomaly;
  8-step RCA before any fix.
- **`testing-validator`** — blocks "it works" claims lacking the R10 proof;
  owns the 4-tier confidence table (must match CLAUDE.md).
- **`layer-validator`** — pre-edit `charly.yml` sanity gate; defers the full
  schema to `/charly-image:layer` + `charly box validate`.

An agent's narrowed `tools:` frontmatter (e.g. `layer-validator`'s
Read/Grep/Glob) is ROLE-lane discipline — it keeps enforcers gating and
executors running — never a security boundary: security lives at the candybox
wall (CLAUDE.md "Candyboxing"), and inside the box every agent gets the full
candy store.

Invoke by name in a prompt, `@`-mention, or the `Agent` tool (scoped id
`charly-internals:<name>`). Custom agents load at SESSION START, so the shipped
workflows do NOT depend on `agentType:` — they inline each agent's role in a
self-contained `agent()` prompt + `schema`, which runs even before a reload
registers a newly-added agent. Reach for `agentType:` only once the agent is
loaded (a fresh session) or when reusing the definition as an agent-team
teammate.

## The shipped workflows (`.claude/workflows/`)

- **`/verify-beds [bed …]`** — the commit-gating full-live-test fan-out, also
  usable for continuous verification throughout development. Runs each
  check bed (default: all) **in parallel** via `parallel()`, bounded by
  the runtime's 16-concurrent agent ceiling (KVM/libvirt are multi-tenant,
  podman builds distinct image tags concurrently), and aggregates pass/fail.
  Beds skipped for a missing host prereq are logged, never silently dropped.
- **`/audit-deploy-configs [image|deploy …]`** — validates + `charly check box`
  + optional `charly check live` + `deploy-verifier` over a set of deploy configs;
  aggregates a health report. Serves the "evaluate deployment configs, for you and your agents" goal.
- **`/triage-check-failure <bed>`** — competing-hypotheses RCA of a failed bed
  run: parallel `root-cause-analyzer`-style agents each validate a hypothesis
  on the live bed, cross-check adversarially, converge on the root cause, and
  hand back a fix to re-run the real bed (per R1).
- **`/verify-status [substrate …]`** — substrate-coverage fan-out for the
  unified `charly status` surface: for each substrate (pod / vm / local / android) it
  runs the bed that exercises it (`check-pod` / `check-k3s-vm` / `check-local` /
  `check-android-emulator-pod`) to completion and aggregates a verdict keyed on
  that bed's `status-shows-*` deploy-scope assertion. Same parallel +
  skip-logging discipline as `/verify-beds`.

## Implementation workflows are bed-scoped too — never sequential codegen + review

The shipped workflows above VERIFY. A dynamic workflow that **implements** a
cutover (fans the coding out across `agent()` calls) obeys the SAME bed-scoped
discipline as an agent team — it is the workflow expression of the B3 model
(`/charly-internals:git-workflow`), not an exemption from it:

- **Partition the parallel work by check bed.** One disjoint disposable
  bed per parallel owner (`check-pod` / `check-k3s-vm` / `check-local` /
  `check-android-emulator-pod` / …). Distinct beds get distinct container/VM/image
  names; the author assigns each disjoint host ports too (the loader does NOT
  check ports — an overlap fails the second bed at deploy), so they run
  concurrently and safely.
- **Check-test at EVERY stage, never only at the end.** Each parallel owner
  **verifies before it changes** (Risk Driven Development — proves its bed's
  high-risk assumptions, above all the composition, on its live bed/backend
  first, never trusting a doc or the code for a high-risk call) and runs its
  bed's real `charly check run <bed>` as the fresh-rebuild R10.
- **Read-only review is an ADDITIONAL layer, NEVER a substitute.** A workflow
  that replaces real-deployment bed runs with a read-only diff-review phase is a
  protocol violation — the opposite of this skill and of CLAUDE.md "Agents,
  Workflows & Teams". Adversarial diff review is welcome ON TOP of the beds.
- **Compile-coherence is solved structurally, not by serializing.** A single Go
  package can't have N agents edit-and-build at once, but that is handled by
  shape, not by abandoning parallelism: the lead lands the **shared core first**
  (compile-clean), each parallel unit is an **independent `init()`-registered
  file** (no shared-file edits), and the one shared host **`charly` binary rebuild is
  a single barrier** between the parallel-implement and parallel-bed-R10 phases.
  Canonical shape: `Core (seq) → Implement (parallel by bed) → Integrate+build
  (seq barrier) → BedR10 (parallel by bed) → Review (parallel, read-only,
  optional)`. **The barrier is load-bearing because `charly` enforces a stale-binary
  freshness guard** — it refuses heavy ops (`image build`, `deploy add`) whenever
  any `charly/*.go` source is newer than the installed `/usr/bin/charly` (remediation:
  `task build:charly`). A teammate editing `charly/*.go` WHILE another's bed is mid-run
  trips that guard on the bed's deploy step, so rebuild ONCE at the barrier, then
  run every bed against the now-stable binary.
- **Same binding rule** as below: disposable-only, commit-gated-not-run,
  no-scope-shrinking-flags, paste-proof survives delegation.

## The binding rule: running a bed is R10-class

`charly check run <bed>` and `charly update` perform an unattended destroy + rebuild.
Therefore, for ANY agent or workflow that runs them:

- **Disposable-only (R10 / Disposable-Only Autonomy).** The sole authorization is the bed's explicit
  `disposable: true`. Agents run disposable check beds, never arbitrary deploys.
- **The commit is gated, not the run (Hard Cutover by Default).** The git commit happens ONLY
  after a full live test of EVERYTHING — the FINAL code, on `disposable: true`
  beds — passes and is pasted. Running `/verify-beds`, `check-bed-runner`, or
  any `charly check run` THROUGHOUT development — in parallel or in the background,
  to validate assumptions before you change and to diagnose errors — is
  ENCOURAGED. A run that passes on an *intermediate* state simply does not
  authorize the commit; only the full final-code run does.
- **No scope-shrinking flags (R10 flag-override clause).** Never pass `--no-rebuild` / `--keep`
  / `--on-*` / scenario filters unless the user named the flag this turn.
- **Paste-proof survives delegation.** Sub-agents are built to *summarize*,
  but R10 demands *pasted* proof. The executors return the raw verdict + exit
  code + failing-log tail; the **delegating (main) agent pastes it** into the
  conversation. A delegated bed run whose failure is summarized away is the
  exact fraud pattern the project bans.
- **Handling a long-running bed — by mechanism, not by who owns it.** A
  VM/emulator bed (`check-k3s-vm`, `check-android-emulator-pod`, the bootstrap-VM
  beds) runs for minutes-to-tens-of-minutes and its libvirt domain / emulator
  OUTLIVES a single turn. Run it by the mechanism, not a who-owns-it rule:
  - **Launch as a harness-tracked background task** (`run_in_background`). NEVER
    foreground — the Bash tool's `timeout` (120s default, 600s maximum, its
    `max` setting — NOT any charly constant) kills the call mid-`vm-create`,
    orphaning the domain. NEVER a sleep/poll loop to "keep it alive" — that
    busy-poll is the exact R4 bandaid this replaces.
  - **The completion notification is the signal, not polling.** The harness
    re-invokes the LAUNCHING session with a `<task-notification>` when the run
    exits, so the launcher must SURVIVE to completion to receive it. The
    persistent main session does. An ephemeral sub-agent does NOT (the `Agent`
    tool returns synchronously — its background children die when it returns),
    and an idle teammate does NOT (its process tree is torn down on idle) — both
    orphan the bed. **Every full `charly check run <bed>` belongs to the persistent
    session as a background task — the only session that survives across turns to
    be notified.** Duration-independent: there is no time budget, and the Bash
    600s figure is a FOREGROUND cap that never applies to a backgrounded bed.
    Sub-agents/teammates do bed-local edits + short foreground checks
    (`charly check box`), never the full run.
  - **Reconnect via durable state, never a held process handle.**
    `.check/<bed>/<calver>/summary.yml` (overall `ok:` + per-step status) + the
    live domain/container ARE the source of truth: "done + verdict" =
    `summary.yml` exists; "still alive" = the `charly check run` orchestrator is in
    the process table. On a suspected orphan — a `running` domain with NO live
    orchestrator — `charly vm destroy <entity>` (or `charly remove <name>`) before
    re-running. You re-derive state from disk; you never "lose" a run.
  - **Paste-proof survives (R10 paste-proof).** The owner reports the verbatim
    `summary.yml` verdict + exit code; the lead pastes it.

## Hooks doctrine — pointer reminders + deterministic gates (not rule-body copies)

Hooks in this project do TWO things and nothing more. The full inventory
(`.claude/hooks/`, wired in the committed `.claude/settings.json`):

| Hook | Event | Role |
|---|---|---|
| `runtime-verification-reminder.sh` | `UserPromptSubmit` | pointer roster: full R0-R10 + RDD + ADE as second-pass triggers |
| `end-of-turn-challenge.sh` | `Stop` | pointer: re-audit vs R0-R10 + Acceptance checklist + per-repo CHANGELOG entry (soft, exit 0) |
| `team-coordination-reminder.sh` | `TaskCreated` / `TaskCompleted` / `TeammateIdle` | pointer: bed-scoped team model (soft, exit 0) |
| `pre-commit-gate.sh` | `PreToolUse(Bash)` | deterministic gate (exit 2 blocks) |
| `pre-push-gate.sh` | `PreToolUse(Bash)` | deterministic gate (exit 2 blocks) |

1. **Pointer reminders** that POINT to CLAUDE.md / skill section names. The
   `UserPromptSubmit` reminder names the FULL R0–R10 + RDD + ADE roster as terse
   second-pass *triggers* (rule label + a few-word essence + an anchor) so every
   rule gets a "verify THIS turn against it" nudge; the `Stop` reminder prompts a
   re-audit of the turn's changes + the per-repo CHANGELOG entry. They are
   reminders, NOT copies: a trigger never restates the rule BODY — CLAUDE.md is
   the single current source, and that is where each trigger points (duplicating
   rule bodies drifts).
2. **Deterministic `PreToolUse` gates** that BLOCK (exit 2) only unambiguous,
   CLAUDE.md-stated invariants: hook bypass via `--no-verify` (`git commit
   --no-verify` — the `-n` short alias, bundled forms included, scanned as a
   flag BEFORE the message provider — AND `git push --no-verify`) or via a
   `core.hooksPath` override in git's global options (`git -c
   core.hooksPath=… commit/push` — the config spelling of the same bypass;
   the scan covers the global-opts span only, so `git commit -c <commit>`
   and a message mentioning the key never false-trigger, and env-var config
   injection is out of scope: the gate is a discipline backstop, not a
   security boundary),
   a missing `Assisted-by: Claude (<tier>)` trailer on an inline `-m` message
   (every commit Claude is involved in must attribute — a pure-human hand-commit
   never reaches this PreToolUse gate; scoped to the commit invocation's own arg
   span; a `-F`/heredoc/command-substituted message is not scanned for absence —
   tier legality still applies), any tier OUTSIDE the legal-on-commit set
   {`fully tested and validated`, `analysed on a live system`, `documentation
   reviewed`} (the AI-Attribution table forbids `theoretical suggestion`
   everywhere and pairs `syntax check only` with "do NOT commit"), the
   `documentation reviewed` tier on a commit whose staged diff is NOT
   all-documentation (`*.md`/CHANGELOG/README/LICENSE/VISION/`*.txt`,
   comment-only code edits, or a submodule pointer bump to an all-documentation
   submodule commit — the tier-vs-diff coherence check, conservative-safe:
   it never lets a behavioral change pass as docs), force-push
   (`git push --force` / `--force-with-lease` / `-f`, bundled forms included),
   and a RUNTIME-tier commit (`fully tested and validated` / `analysed on a live
   system`) that stages no `CHANGELOG/<YYYY.DDD.HHMM>.md` entry in a repo that tracks a
   `CHANGELOG/` (history -> each repo's per-repo per-CalVer `CHANGELOG/`; exempt: a
   repo with no `CHANGELOG/`, and a commit whose staged diff is EXCLUSIVELY
   submodule pointer bumps — fires only when an inline tier is parsed, like the
   absent-trailer check).

The honest division of labor: **hooks gate mechanical invariants; agents
judge proof.** Whether a tier is *justified* by the evidence is a reasoning
task — that stays with `testing-validator` + the pasted-proof rule, NOT a
regex in a hook. Never re-bloat the reminders into CLAUDE.md rule-body copies —
name + point, never restate.

## Agent teams (experimental — enabled in committed settings)

Agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) are **enabled in the
committed `.claude/settings.json`** (`env` block). The experimental caveats
remain: no in-process session resume (`/resume`/`/rewind` don't restore
teammates), one team at a time (clean up before creating another), no nested
teams (only the lead manages the team), and the lead is fixed for the team's
lifetime. Enabling requires a `claude` restart, because the `env` flag is read
at process start.

Teammates reuse the same agent definitions as roles — their `tools` + `model`
apply; the `skills`/`mcpServers` frontmatter does NOT on the team path (each
teammate loads `CLAUDE.md` + project/user skills on spawn, like any session).
Set the **Default teammate model** in `/config` (pick "Default (leader's
model)" to inherit). The `TaskCreated` / `TaskCompleted` / `TeammateIdle` hooks
can enforce gates (exit 2 = block + feedback); the shipped
`team-coordination-reminder.sh` is a soft pointer (exit 0).

### Bed-scoped parallel real-deployment testing

The **check bed is the unit of ownership, isolation, AND throughput** — it
replaces the git worktree. `charly check run <bed>` runs exactly ONE bed; the
old strictly-SEQUENTIAL roster sweep was removed precisely because its
wall-clock ≈ the SUM of every bed, so running a roster means N concurrent
`charly check run <bed>` processes — one per agent — and **every full
`charly check run <bed>` is a long, multi-turn background task whose OWNER must
survive across turns to receive the completion notification.** A bed run is launched with `run_in_background` (uncapped — it runs
across turns; the Bash 600s figure is a FOREGROUND cap that never applies) and
re-invokes its launching context when it exits. **Empirically verified (2026-06,
this host) which contexts can own a bed:**

- ✓ **The persistent main session** — launches each bed as its own
  `run_in_background` task; re-invoked on completion (proven by surviving
  wake-timers). The headless default mechanism.
- ✓ **A background agent** (`Agent` tool, `run_in_background`) — a separate
  supervisor-managed process that persists, runs to completion, and reports
  (proven: a 100s task completed + reported back). A per-bed out-of-process owner
  that works headless. Caveat: its INTERNAL `charly check run` is one foreground call
  (600s-capped), so for a long bed prefer the main-session `run_in_background`
  task or step the bed.
- ✓ **A split-pane teammate** — a separate persistent process, so it CAN own a
  bed. ONLY in an interactive **tmux/iTerm2** run (`teammateMode: tmux` AND the
  lead's own process launched inside tmux, `TMUX` set). NOT available headless.
- ✗ **An in-process teammate** (the headless `teammateMode: auto` default) —
  CANNOT own a bed that outlives a turn: its `run_in_background` task is TORN DOWN
  the instant it yields (verified 4× — marker absent, no process, never
  re-invoked). It runs bed-local EDITS + short foreground checks (`charly check box`,
  `charly box validate`) only, never the full `charly check run`.

So **"one agent ⇄ one bed" = one PERSISTENT owner per bed**, launched
longest-pole-first: headless → the persistent session runs N concurrent
`run_in_background` bed tasks (or a background agent per bed); interactive tmux →
a split-pane teammate per bed. NEVER an in-process teammate.
Two load-time mechanisms back the isolation: the bed set is DERIVED from the
disposable deploys (`CheckBeds()`) — a bed is just a `disposable: true` deploy, so
it shares the deploy namespace's global name-uniqueness and can't collide with
another deploy by construction — and `validateCheckBeds` requires every bed to set
`disposable: true` and to resolve to a substrate (pod / vm / local / android, with
the referenced vm/local/android entity present). Distinct beds therefore get distinct `charly-<bed>`
container / libvirt-domain / image names. **Host-port disjointness is NOT
statically guaranteed** — neither mechanism checks ports; assigning each bed
non-overlapping host ports is the AUTHOR's responsibility, and an overlap
surfaces only at deploy time when `CheckPortAvailability` fails the SECOND bed's
`start`. Partition beds with disjoint ports BY CONSTRUCTION — the loader will
not catch an overlap for you. A bed pins an image → layers → files, so owning a
bed owns those source files.

Each bed is a **candybox** (CLAUDE.md "Candyboxing"): a disposable, secured
deployment stocked with the FULL `charly` + MCP + `charly check` toolset, so the bed's
owner can build / deploy / prove the real thing inside its boundary and rebuild
it fearlessly — never a tool-restricted sandbox.

The playbook:

1. **Lead partitions the beds** so no two teammates own the same bed's source.
2. **A PERSISTENT owner runs each bed; in-process teammates edit + short-check.**
   The full `charly check run <bed>` (build → check image → deploy → check live → fresh
   `charly update` → teardown) runs as a `run_in_background` task on a PERSISTENT
   owner: headless → the lead/persistent session (one `run_in_background` task per
   bed, or a background agent per bed); interactive tmux → a split-pane teammate
   per bed. It follows the `check-bed-runner` verbatim-verdict discipline; failures
   triage via `root-cause-analyzer`. IN-PROCESS teammates (the headless default)
   do bed-local EDITS + short foreground checks (`charly check box`,
   `charly box validate`) ONLY — they cannot run a full bed (their bg dies on
   yield). Review/RCA are auxiliary — never a substitute for the live run.
3. **Verify before you change (Risk Driven Development)**: each teammate proves
   its bed's HIGH-RISK assumptions — above all the composition — on its standing
   bed BEFORE editing, never trusting a doc or the code for a high-risk call, so
   it is never disproven hours later.
4. **Default parallel, longest-pole-first.** Beds run concurrently — there is NO
   `charly` concurrency cap (the "16-concurrent / 1000-total" figure is only the
   dynamic-workflow harness ceiling); the real limit is host CPU/RAM/podman, and
   there is no global build lock (pod beds take no ledger flock, `.build/<image>`
   is per-image). KVM/libvirt are multi-tenant and podman builds distinct image
   tags concurrently, so pod and VM beds run alongside each other. **The real
   concurrency ceiling is podman's single sqlite container-store write lock — NOT
   CPU.** Every container op (each build stage, `podman run --rm` probe, pod create,
   teardown `rm`) takes a write transaction on the one graphroot DB; under many
   concurrent bed cycles the lock is contended past its busy-timeout and ops fail
   with `Error: beginning transaction: database is locked` (exit 125), cascading into
   probe/build/deploy failures across the whole roster. Measured on 16C/123 GB: at
   **maxjobs 14 → 0 locks** (12/13 beds pass), at **maxjobs 22 → EVERY bed hit
   `database is locked`**. So the un-tuned ceiling is ~14-20 concurrent beds. It is
   NOT CPU (RAM/disk have huge headroom — 83 GB + 1.4 TB free at peak; load 22-24 is
   fine) and NOT orphans alone.
   **The fix that RAISES the ceiling is `transient_store = true`** (`~/.config/
   containers/storage.conf` `[storage]`, or podman's global `--transient-store`
   flag): container run-state moves to a per-boot tmpfs DB, so the high-churn
   container ops stop contending on the graphroot lock; images stay persistent in
   graphroot. PROVEN — the SAME maxjobs 22 that locked EVERY bed → **0 `database is
   locked`, 32/37 pass** with transient_store on. Enable it on any host running the
   roster concurrently (set `[storage] driver/graphroot/runroot` to the host's real
   values + `transient_store = true`). Tradeoff: containers don't survive reboot
   (quadlet services recreate from image+volumes; volume DATA persists) — fine for an
   ephemeral eval host. Complementary hygiene (a landed fix, NOT the concurrency fix):
   the check-box reap names each probe container `charly-probe-<pid>-<seq>` and
   force-reaps it (`reapDisposableProbe`, `charly/deploy_executor_nested.go`) so a
   killed probe never leaves an orphan.
   Partition by expected DURATION, not bed count: start the long poles (VM/desktop
   beds, as persistent-session background tasks) FIRST and overlap the cheap pod
   beds underneath, so wall-clock ≈ the slowest single bed.
   **RDD discipline, learned the hard way here:** a `database is locked` /
   `signal: killed` (a probe hung ON the store lock, then timed out) / build crash
   under concurrency is the STORE LOCK — enable transient_store — almost never CPU.
   Two wrong hypotheses each cost a cutover on this campaign — "CPU oversaturation"
   (bogus load-gate) and "cache-mount race" (bogus `sharing=locked`) — purely because
   the ACTUAL error line (`database is locked`) was assumed instead of READ (an R1
   violation). ALWAYS read the real error; then isolate any bed failure by re-running
   it ALONE: **passes alone but fails in a pool → the shared store lock** (transient_
   store), **fails alone too → a real deterministic bug** (e.g. the pixelflux 404 a
   fragile `curl -sL | tar` masked as `tar: Child returned status 1`). With the store
   lock removed, RAM/disk/CPU have enough headroom that maxjobs ≈ 20-24 runs cleanly.
5. **The lead owns the single commit**, gated on the consolidated full
   final-code live test (the beds in parallel). Teammates never commit/push.

Worked partition (illustrative): A→`{check-pod, check-local}`,
B→`{check-jupyter-pod, check-versa-pod}`, C→`{check-k3s-vm}` (VM, needs the
libvirt user session), D→`{check-sway-browser-vnc-pod}` (heavy). All concurrent
→ multiple pods *and* a VM live at once; wall-clock ≈ the slowest chain, not
the sum.

### Speed levers (grounded in the real bed cycle)

One-agent-per-bed is the headline speedup; these compound it, each grounded in
how `charly check run` actually behaves:

- **A pod bed builds the image ONCE.** Step 1 (`charly box build`) is the only
  build; the "fresh `charly update`" R10 gate is a `systemctl restart` onto the
  already-built image (`charly update` carries no `--build`, and `EnsureImage`
  short-circuits on `LocalImageExists`). The cost model is ~1 build/bed — never
  pessimistically assume two.
- **Pre-warm the shared base ONCE.** Same-base beds (e.g. two `cachyos` images)
  share cached base layers in podman storage, and the content-derived
  `EffectiveVersion` keeps the base `FROM`-SHA stable so cache misses don't
  cascade. Build the base (or the first same-base bed) once before fan-out →
  every sibling bed's build is incremental, rebuilding only changed layers.
- **`check:`-check iteration is nearly free.** LABELs are emitted LAST in the
  Containerfile, so a check-only edit rebuilds in seconds (every upstream
  RUN/COPY cache-hits). Write check coverage aggressively; only layer/package
  edits pay a full rebuild.
- **`context_ignore` + `--podman-jobs` / `--jobs`** are the legitimate
  build-speed levers (trim the build-context tar; parallelize stages within one
  build and images across a DAG level). On by default.

**Flag discipline — speed levers vs scope-shrinking (never confuse them).** A
"go faster" mandate tempts the forbidden shortcut. LEGITIMATE: `--podman-jobs`,
`--jobs`, `context_ignore`, pre-warming, agent-layer parallelism, longest-pole
scheduling. R10-SCOPE-SHRINKING (need explicit per-turn operator authorization,
CLAUDE.md R10 flag-override clause): `--no-rebuild` (skips the R10 fresh-update
gate), `--keep`, `--skip-rebuild`. "To go faster / to fit the session" is the
confession, not the defense. The full flag catalog + rule:
`/charly-check:check` "Flag discipline".

## Cross-References

- `/charly-check:check` — the bed surface these agents/workflows drive (`charly check
  run`/`image`/`live`, the disposable check-bed inventory, exit codes).
- `/charly-internals:disposable` — why `disposable: true` is the sole destroy
  authorization.
- `/charly-internals:git-workflow` — the R10-gated landing the executors feed.
- `/charly-internals:skills` — agent/skill discovery + the signpost convention.
- CLAUDE.md "Agents, Workflows & Teams" + R10 / "Hard Cutover by Default" + AI Attribution.

## When to Use This Skill

Invoke before authoring or invoking an charly sub-agent / dynamic workflow /
agent team, before wiring agent-lifecycle or commit/push gate hooks, and
whenever deciding which primitive should drive the `charly check` beds for a given
verification.
