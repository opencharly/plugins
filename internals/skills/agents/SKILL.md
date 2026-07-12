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

## Delegation IS fresh context — the primitives' primary purpose

A sub-agent, teammate, or workflow agent runs with its OWN full, fresh context budget, independent of the orchestrating session's. That makes delegation the ANSWER to context pressure, not a reason to stop. When a cutover — or a whole multi-cutover program — is bigger than the context you have left, you do NOT halt and tell the user to "start a fresh session on task #N". You SPAWN a fresh teammate / sub-agent (`Agent`, an agent team, or a workflow), hand it the unit of work, and it executes end-to-end with fresh context while you keep orchestrating and land the result. **That teammate IS "a fresh session," delivered on demand, inside the same autonomous run.** A large program is executed by driving a teammate per cutover (or a team per stage) to merged PRs — one clean atomic cutover per teammate, orchestrated by the persistent session, never deferred to a future human-started session. Reach for delegation BEFORE you feel context pressure. "I need a fresh session / a fresh context / I've exhausted context / continuing would break the tree" are FORBIDDEN excuses (CLAUDE.md "Hard Cutover by Default" + `/charly-internals:cutover-policy`) — the autonomous loop never stops for context: it compacts-and-continues, decomposes, or delegates. The disposable-only + paste-proof + no-scope-shrinking-flags binding rules below apply to a delegated cutover exactly as to a directly-run one.

**A handoff PRESERVES in-flight WIP via the WORKTREE + a handoff package — NEVER a
"checkpoint commit."** When half-done work crosses a boundary (a teammate hands off, or a
session delegates a mid-flight unit), the durable carrier is the non-destructive git
WORKTREE — the uncommitted working tree on its `feat/<slug>` branch — plus a HANDOFF PACKAGE
(the branch + absolute worktree path, the WIP state, the exact next steps, any captured
patch). It is NEVER a "checkpoint commit": un-R10'd non-docs code CANNOT be committed at any
honest tier — `syntax check only` pairs with "do NOT commit" and a runtime tier needs a live
R10 that has not run, so the `pre-commit-gate` + attribution rules BLOCK it. The receiving
agent reads the package, confirms the worktree (`git -C <path> status --short` lists the WIP),
and continues from the working tree — the WIP was never at risk because nothing destructive
touched it, and the worktree is exactly where a fresh context resumes.

**Verify every delegate decision — a teammate/sub-agent report is a CLAIM (never-trust-verify
applies to delegates exactly as to docs and memory).** Before ACCEPTING any decision, finding,
or scope-change a delegate proposes, the ORCHESTRATOR verifies its 1–3 LOAD-BEARING claims
itself — read the named file:line, run the grep/count, or (for a HIGH-RISK behavioral claim)
demand/run the disposable-bed spike — and records the verification in the ruling; a claim it
could not verify is flagged as unverified, never silently trusted. This is cheap (greps and
reads) and it pays both ways: a confirmed claim puts the ruling on ground truth, and the
misses are exactly the ones that would poison every dependent worker (live examples from one
orchestration wave: an "additive" sdk move that was actually a cross-cutover type-graph hub; a
hand-written wire type justified by a rationale the mandated `gengotypes` spike then overturned
— while CONFIRMING the conclusion via the real inexpressible; two teammates defining the same
wire type in two schema files within minutes). Validator findings get the same treatment —
re-read the flagged lines before fixing. Delegates' own claims about EACH OTHER'S scope
(file-ownership, "X already moved Y") are the highest-risk class: verify against the tree, not
the message.

## The default multi-agent execution model — a most-capable orchestrator driving cost-scaled teammates

For any SUBSTANTIAL or multi-cutover program, the DEFAULT topology is a single
**persistent ORCHESTRATOR** session coordinating **parallel TEAMMATES** (one per
in-flight cutover) and **fresh `pr-validator`s** (one per ready PR) — with the
model tiers split by leverage, not evenly (next subsection). This is the proven
default — not opt-in,
not "when convenient"; solo/sequential execution is the EXCEPTION, reserved for
trivial single-file or conversational work. The model COMPOSES the pieces this
skill and `/charly-internals:git-workflow` already own (the bed-scoped partition,
the fresh independent `pr-validator` two-step landing, delegation-is-fresh-
context, concurrent landings) — it does not replace them, and the sections below
LINK to each rather than restate it.

### Model-tier split — most-capable orchestrator, cost-scaled workers

The orchestrator runs ×1 — ONE persistent session — and carries the
HIGHEST-LEVERAGE reasoning: routing each ready PR to a fresh validator,
sequencing the merge instants, running the per-merge delta re-gate, owning the
long beds (`run_in_background`, see "Handling a long-running bed" under the
binding rule), rebase-broadcasting to the siblings, and — above all — the
independent RDD-VERIFICATION of EVERY teammate decision (the correctness
backstop for the whole parallel run; next subsection). The teammates run ×N in
parallel, each on a BOUNDED unit (one cutover, one PR) UNDER that verification.
That ×1-vs-×N shape, not a "who reasons harder" split, decides the tiers:

- **Orchestrator → the MOST-CAPABLE (most-expensive) model.** The premium is
  paid ONCE (×1, resident across the whole program) and buys the top tier
  exactly where the leverage is highest — the coordination and the
  every-decision verification that backstop correctness for the entire run.
- **Teammates + `pr-validator`s → a LESS-EXPENSIVE model.** They scale ×N with
  the parallel width, each bounded to one cutover / one PR and backstopped by
  the orchestrator's verification, so the cheaper tier carries the parallel bulk
  affordably.

The economics: a ×1 top-tier orchestrator + ×N cheaper-tier workers minimizes
total cost while keeping the correctness reasoning at the top tier. State the
PRINCIPLE (most-capable orchestrator + cost-scaled teammates) and the cost
RATIO, NOT exact prices (they rot) — the current instantiation is a **Fable-5**
orchestrator (~2× the teammate model's per-token cost) driving **Opus-4.8**
teammates and validators. Set the default teammate model in `/config` to the
CHEAPER tier; the lead/orchestrator runs the TOP tier (a teammate or validator
may still be spawned with an explicit `model:` when a unit needs it).

### Maximum parallelization is the DEFAULT

Run every independent unit at once: multiple cutovers implemented concurrently
(one teammate each, partitioned so no two share a bed's source — the
"Bed-scoped parallel real-deployment testing" invariants below are the partition
contract), multiple PRs validated concurrently (one fresh `pr-validator` each,
independent contexts that couple only at the merge instant), first-ready-first-
merged. There is no benefit to holding a ready PR for a sibling; the only
inherent ordering is the merge instants and a real dependency DAG.

### Slot budget — a persistent slot is a concurrent CUTOVER, not an agent

The parallel width above is bounded by a FINITE resource: the persistent
teammate SLOTS (the operator's live-oversight panes). Spend them by the right
unit — a slot ≈ ONE concurrent INDEPENDENT cutover, NEVER a headcount of agents:

- **Sequential sub-phases WITHIN one cutover do NOT each claim a slot.** The
  owning session COMPACTS-AND-CONTINUES across its own phases (design → implement
  → land) and delegates only MECHANICAL BULK (a wide sweep, a batch edit, a
  fan-out search) to a TRANSIENT sub-agent that FREES its slot on return — never a
  new PERSISTENT teammate per sub-phase. One cutover = one persistent owner, not
  one-owner-per-phase.
- **Validators and design-reserve agents are TRANSIENT / RECYCLABLE.** A fresh
  `pr-validator` and any spun-up design/scout agent exist only for their role;
  STOP them the instant the role completes so the slot returns to the pool — see
  "Agent lifecycle hygiene — stop what you spawned" below.
- **On slot EXHAUSTION, STOP STALE AGENTS — never downgrade the model.** When a
  new teammate/validator cannot spawn, the fix is to reclaim slots from FINISHED
  agents (lifecycle hygiene below), NEVER to switch to a headless / in-process
  teammate mode: the panes ARE the operator's live oversight of every agent, a
  standing requirement, so trading oversight for headroom is forbidden.

State the PRINCIPLE (slots = concurrent cutovers; transient bulk frees its slot;
stop-don't-downgrade on exhaustion), not the host-specific pane count.

### Concurrent landing — link, don't restate

Landing stays concurrent WITH branch protection `strict: true` KEPT. The
mechanism — after each merge, `gh pr update-branch` every still-open sibling PR,
then a RISK-PROPORTIONAL DELTA RE-GATE (empty merged-delta ∩ branch-files →
rebuild + `go test ./...` + lint + re-post status; non-empty → additionally
re-run the affected beds; a full roster re-run only when the overlap hits the
cutover's risky shared paths) — is owned by `/charly-internals:git-workflow`
"Concurrent landings — N open cutovers do NOT serialize beyond git itself". The
orchestrator DRIVES it; it is not restated here. Zero-overlap PRs (e.g. a
test-only PR and a config PR) therefore never block each other.

### The orchestrator RDDs every decision — bidirectionally

"Verify every delegate decision" (above) is not a one-way audit. The orchestrator
independently RE-DERIVES every teammate decision before accepting it — scope,
mechanism, and coverage — by reading the code, running a bed, or observing live
state, and CORRECTS under-scoping, over-scoping, and coverage gaps; it never
rubber-stamps. Teammates likewise correct the orchestrator, so the verification
is BIDIRECTIONAL ("fractal verification"), and it is load-bearing: it catches
concurrency defects invisible to any serial run — a shared-domain collision (a
defect of the class "Bed-scoped parallel real-deployment testing" below
catalogs) surfaces only under simultaneity — as well as under-scoped bed
rosters, coverage gaps in a drop-vs-nest call, and stale rebase bases, none of
which a one-way audit reveals. The RDD instrument is identical for a delegated decision
and for your own: a HIGH-RISK claim is proven on a live `disposable: true` bed,
never accepted on a teammate's report alone.

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
- **`pr-validator`** — the FRESH PR evaluator (the disposing half of the two-step
  landing). Spawned with NEW context, it independently re-validates a PR against
  R0–R10 + the relevant skills, posts the `charly/claude-validation` commit status,
  and ONLY on PASS generates the merge-time CalVer, rewrites the version surfaces
  on the feat branch, merges (`gh pr merge --squash`), and tags. It is the ONLY
  actor that posts the status or merges; branch protection makes its status the
  mechanical gate. NEVER the agent that authored the PR — the point is independent
  evaluation. See `/charly-internals:git-workflow` (B1 step 2, B5).

**Every roster agent runs UNRESTRICTED — its spec OMITS the `tools:` field**, so it
inherits ALL tools (the full set the main session has: Read / Bash / Edit / Write /
Skill / SendMessage / Agent / Task* / … + MCP tools + full plugin-skill-by-name
access), exactly as CLAUDE.md "Candyboxing" mandates: *never secure by whitelisting
commands; trust the walls, not the tools.* The wall is the disposable target +
branch protection + the validator's fresh-context independence — NEVER a narrowed
tool set. An agent's ROLE (enforcer vs executor) is defined by its PROMPT + spec,
NOT by a tool whitelist: a whitelisted `tools:` is the Candyboxing anti-pattern.
Tools and skill access are TWO INDEPENDENT concerns (invariant #4 below): omitting
`tools:` makes the agent inherit ALL tools — verified equivalent to the built-in
general-purpose agent (`Tools: *`) for **tool inheritance** — but it does NOT make
`Skill(<name>)` resolve a charly-* skill, which depends on per-session skill
registration a sub-agent usually lacks (a live `Tools: *` validator still got
`Unknown skill`). So an agent reaches a charly-* skill by **`Read`ing its `SKILL.md`
by path — the reliable method**; `Skill(<name>)` is an optional fast-path that may
return `Unknown skill`, and that failure is EXPECTED, never "skills unavailable". Do
NOT add a `tools:` line to a roster agent — omission is the documented way to inherit
all tools (`tools: "*"` is NOT valid and yields ZERO tools).

Invoke by name in a prompt, `@`-mention, or the `Agent` tool (scoped id
`charly-internals:<name>`). Custom agents load at SESSION START, so the shipped
workflows do NOT depend on `agentType:` — they inline each agent's role in a
self-contained `agent()` prompt + `schema`, which runs even before a reload
registers a newly-added agent. Reach for `agentType:` only once the agent is
loaded (a fresh session) or when reusing the definition as an agent-team
teammate.

## The shipped workflows (`.claude/workflows/`)

- **`/verify-beds [bed …]`** — the commit-gating fan-out for the beds a SUB-AGENT
  CAN OWN. It runs the **SHORT** beds in parallel via `parallel()`, bounded by the
  runtime's 16-concurrent agent ceiling (KVM/libvirt are multi-tenant, podman builds
  distinct image tags concurrently), and aggregates pass/fail. It **DEFERS** every
  LONG bed — a `vm`/`android` substrate, or any bed whose newest
  `.check/<bed>/<calver>/summary.yml` records `total_seconds >= 600` — returning them
  in `deferredLongBeds[]` with the exact command, because an `agent()` sub-agent cannot
  own a bed that outlives its turn (see 4c below); the PERSISTENT session runs each as a
  `run_in_background` task. It **REFUSES** every HOST-LOCAL bed (a `local:` deploy, or a
  bed with a nested `local:` member, whose `host:` is `local`) — those apply candies to
  the operator's workstation and belong in a disposable eval VM. Deferrals, refusals,
  and missing-host-prereq skips are all logged and returned; **`gateComplete: false`
  means the roster is PARTIAL and is not a green R10 gate.**
  *An edited `.claude/workflows/*.js` is NOT what `Workflow({name})` runs — the registry
  is snapshotted at session start. Drive an edited workflow with `Workflow({scriptPath})`,
  which takes precedence.*
- **`/audit-deploy-configs [image|deploy …]`** — validates + `charly check box`
  + optional `charly check live` + `deploy-verifier` over a set of deploy configs;
  aggregates a health report. Serves the "evaluate deployment configs, for you and your agents" goal.
- **`/triage-check-failure <bed>`** — competing-hypotheses RCA of a failed bed
  run: parallel `root-cause-analyzer`-style agents each validate a hypothesis
  on the live bed, cross-check adversarially, converge on the root cause, and
  hand back a fix to re-run the real bed (per R1).
- **`/verify-status [substrate …]`** — substrate-coverage **PLAN** for the unified
  `charly status` surface. It **runs NO beds.** Every substrate bed is disqualified
  from sub-agent ownership: `check-pod` (measured ≥600s), `check-k3s-vm` (vm),
  `check-android-emulator-pod` (android), and `check-local` (**host-local** — it
  applies candies to the operator's workstation). A runner form is therefore invalid
  by construction. It emits, per substrate, the exact `charly check run <bed>`
  command, the `summary.yml` path to read, and the `status-shows-*` deploy-scope
  assertion that bed proves; the **persistent session** owns each run as a
  `run_in_background` task, and the `local` bed runs inside the disposable eval VM,
  never on the host. `gateComplete` is `false` by construction. The bed-safety
  classifier lives in ONE place — `/verify-beds` — and is not duplicated here (R3).

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

## Sub-agent operational invariants — the autonomous loop depends on these

Three mechanics, each proven on this host, that decide whether an autonomous
landing works at all. Violating any one silently breaks the loop.

**1. A sub-agent's PROJECT ROOT is its working directory — never `cd` into a
submodule.** Claude Code resolves `.claude/settings.json` (and therefore
`permissions.allow`) from the agent's project root, and keys
its transcript directory the same way (`~/.claude/projects/<cwd-with-slashes-as-dashes>/`).
A sub-agent told to work *inside* `plugins/` or `sdk/` roots there — and those
submodules ship **no `.claude/`** — so it silently loses the SUPERPROJECT's committed
permission rules. It does not warn; it just gets denied later, for reasons that read
like a policy problem. Drive every submodule action from the superproject with a
LITERAL absolute path: `git -C /abs/path/plugins …` and `gh … --repo <owner>/<repo>`
(the same rule `/charly-internals:git-workflow` B7 states for the commit gate — it is
equally load-bearing for PERMISSIONS). **Proven by controlled experiment:** a
`pr-validator` rooted in `plugins/` had even its `success` status POST DENIED
(*"the only authorization comes from a `<teammate-message>`, which is not user
intent"* — the classifier never saw the superproject's standing rule); the SAME agent,
same rule text, rooted in the superproject, posted `success` with **zero denials**.
Rooting fixes the STATUS POST (cleared by `permissions.allow`). **The MERGE is a
SEPARATE, stricter classifier gate — Merge-Without-Review — that `permissions.allow`
does NOT clear** (proven: `gh pr merge` denied for BOTH a superproject-rooted sub-agent
AND the main session despite the rule); it lands only under the operator's `autoMode.allow`
rule (user/managed settings) or fresh in-context user consent, never CLAUDE.md prose. See
`/charly-internals:git-workflow` B5.

**2. A permission denial ENDS the sub-agent's turn — write the verdict durably
FIRST.** The denial text instructs the agent to "STOP and explain to the user", and it
stops; its explanation never reaches the spawning session (observed repeatedly: agents
idle "available" with no report). So every agent that will attempt a permission-gated
action MUST, before attempting it: (a) write its full verdict to a known file path, and
(b) post its PR comment. Posting a **`failure`** status or a comment is NEVER gated —
Self-Approval only blocks marking a check **passed** — so a FAIL verdict is always
deliverable. Then attempt the gated action and append its verbatim outcome to the file.

**3. Reconnect via durable state; never wait on the message channel.** The truth is on
disk and on the API: the PR's statuses + comments, the verdict file, and the agent's own
transcript at `~/.claude/projects/<cwd-slug>/<uuid>.jsonl` (a verbatim classifier denial
is recoverable from there even when the agent died mid-sentence). To WAIT on a condition,
use a `run_in_background` Bash `until`-loop that EXITS when it resolves — foreground
`sleep` is blocked — and make the exit condition cover EVERY terminal state (allowed,
denied, status posted, merged, timed out). **Silence is not success:** a loop that only
matches the happy path cannot distinguish "still working" from "died at a denial".

**4. A sub-agent loads a skill by `Read`ing its `SKILL.md` BY PATH — the reliable method;
`Skill(name)` is unreliable regardless of the tool set.** TWO independent facts, do not conflate
them:
- **Tools:** roster agents run UNRESTRICTED — specs OMIT the `tools:` field → inherit ALL tools
  (documented behavior, equivalent to the built-in `general-purpose` agent, `Tools: *`), per
  CLAUDE.md "Candyboxing" (*trust the walls, not the tools*). A whitelisted `tools:` is the
  anti-pattern; do NOT re-add one to "grant" `Skill`/`SendMessage`/`Write` — omission grants all.
- **Skill access:** invoking `Skill(charly-internals:go)` BY NAME depends on the charly-* skills
  being REGISTERED in that sub-agent's SESSION, which is INDEPENDENT of the `tools:` field and
  usually ABSENT — verified live, an unrestricted `Tools: *` validator got `Unknown skill:
  charly-internals:git-workflow` (its session registry held only built-ins), while `Read`ing
  `plugins/<family>/skills/<name>/SKILL.md` worked every time (proven across multiple validator
  runs). So the RELIABLE method is the file `Read`; `Skill(name)` is an opportunistic fast-path
  that MAY work in some sessions. A `Skill(name)` failure (`Unknown skill` / "not registered") is
  EXPECTED for a sub-agent, NEVER "the skills are absent". Spawn prompts therefore instruct
  `Read`-by-path (giving the SKILL.md PATHS), with `Skill(name)` as an optional shortcut.

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
    live domain/container ARE the source of truth: "done" = `summary.yml` exists;
    "still alive" = the `charly check run` orchestrator is in the process table.
    **But `ok: true` is NOT proof of a pass** — a bed charly SKIPPED for an absent
    host prereq writes `ok: true`, `total_seconds: 0`, and a lone `prereq-*-skipped`
    step; the exit code is the discriminator (**3 = skipped**). See
    `/charly-check:check`. On a suspected orphan — a `running` domain with NO live
    orchestrator — `charly vm destroy <entity>` (the `kind: vm` ENTITY name, NOT the
    bed name: a wrong name exits 0, prints `Destroyed VM …`, and leaves the orphan
    running — confirm with `charly vm list`), or `charly remove <name>` for a pod,
    before re-running. You re-derive state from disk; you never "lose" a run.
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
   a missing `Assisted-by: Claude (<tier>)` trailer on a READABLE message — an
   inline `-m` value, a heredoc body (both live in the command string), or a
   `-F <file>` the gate READS (every commit Claude is involved in must attribute —
   a pure-human hand-commit never reaches this PreToolUse gate; scoped to the
   commit invocation's own arg span). A message the gate CANNOT read to find the
   tier — a `$(...)`/backtick substitution, a piped or unreadable `-F`, or an
   editor message (no -m/-F) — fails CLOSED (inline the trailer with `-m`, or point
   `-F` at a readable file); `--amend`/reuse inherit an already-gated message and
   are exempt. And a command the gate cannot TOKENIZE — an unbalanced or unquoted
   quote, e.g. an apostrophe in a heredoc body — fails CLOSED and is blocked, so
   balance the quotes or use `git commit -F <file>`),
   any tier OUTSIDE the legal-on-commit set
   {`fully tested and validated`, `analysed on a live system`, `documentation
   reviewed`} (the AI-Attribution table forbids `theoretical suggestion`
   everywhere and pairs `syntax check only` with "do NOT commit"), the
   `documentation reviewed` tier on a commit whose staged diff is NOT
   all-documentation (`*.md`/CHANGELOG/README/LICENSE/VISION/`*.txt`,
   comment-only code edits, or a submodule pointer bump to an all-documentation
   submodule commit — the tier-vs-diff coherence check, conservative-safe:
   it never lets a behavioral change pass as docs), a direct push to `main`
   (a `git push` whose refspec destination is `main` / `refs/heads/main` — `main`
   advances ONLY via an agent-validated PR merge; a bare `git push` with no
   refspec is left to the authoritative server-side branch protection), force-push
   (`git push --force` / `--force-with-lease` / `-f`, bundled forms included),
   a commit at ANY legal tier (`fully tested and validated` / `analysed on a
   live system` / `documentation reviewed`) that stages no
   `CHANGELOG/<YYYY.DDD.HHMM>.md` entry in a repo that tracks a `CHANGELOG/`
   (history -> each repo's per-repo per-CalVer `CHANGELOG/`; exempt: a repo with
   no `CHANGELOG/`, and a commit whose staged diff is EXCLUSIVELY submodule
   pointer bumps — the pure-pointer-bump whose narrative lives in the submodule;
   fires whenever a tier is parsed from a READABLE message (inline `-m`, heredoc,
   or a `-F <file>`), like the absent-trailer check — an unreadable message fails
   CLOSED at the attribution stage before this),
   and a commit staging a `*.go` change whose touched MODULE is not
   `golangci-lint`-clean (the Go-lint criterion — the CONFIGURED `golangci-lint
   run`, never `--fix`/`--enable-only`, per touched module with `GOWORK=off` for
   `candy/plugin-*` candies; `unused` needs whole-package analysis so the gate
   lints the MODULE, not just the changed files; fail-OPEN when golangci-lint is
   absent or times out — the `pr-validator` remains the real gate; it exists so
   dead/unused code cannot slip in the way the P10 VM-CLI sweep's 21 orphaned
   symbols did).

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

The **check bed is the unit of ownership, isolation, AND throughput** within one
source tree; across CUTOVERS, a **git worktree with its own built binary** is the
gate-isolation unit (see "Per-worktree binaries" below — the two compose).
`charly check run <bed>` runs exactly ONE bed; the
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
statically guaranteed, so EVERY eval bed MUST use PORT AUTO-ALLOCATION — never a
hardcoded host port.** The loader checks no ports, so a hardcoded host port
shared by two beds surfaces only at deploy time when `CheckPortAvailability` /
passt's `Listen failed … Address already in use` fails the SECOND bed's `start`
(a real concurrency defect this campaign hit: two VM beds both pinned SSH host
`12227`). Manual "pick disjoint ports" deconfliction is FORBIDDEN — it is
fragile authoring that silently collides the moment a bed is added or the roster
runs concurrently. Use auto-allocation BY CONSTRUCTION: a `vm:` bed sets
`ssh: {port_auto: true}` (the runner probes a free host port and persists it in
`vm_state`); a `pod:`/`local:` deploy uses the `port: [auto]` sentinel
(`AllocateAutoPorts` tracks an `occupied` set so concurrent `[auto]` deploys
never collide) and references the assigned port via `${HOST_PORT}` /
`${HOST:<member>:<port>}` in its checks — NEVER a literal host port. A bed pins
an image → layers → files, so owning a bed owns those source files.

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
4b. **Serialize beds that share an EXCLUSIVE host-resource token — the SECOND
   concurrency ceiling, ORTHOGONAL to the store lock.** A bed declaring
   `requires_exclusive:` / `requires_shared:` on a resource token (`nvidia-gpu`
   for the real GPU; a synthetic selector-less token like `test-lock` for the
   arbiter/preempt beds) contends with every OTHER bed claiming the same token:
   the arbiter **FAST-FAILS** a second claim on a held exclusive token
   (`resource nvidia-gpu is held EXCLUSIVELY by "<bed>" — cannot share it`,
   exit 1, ZERO build steps — the bed never builds), because two live claims on
   one exclusive resource is a contradiction, not a queue. So a PARALLEL roster
   must PARTITION by token: each exclusive-token set runs as its OWN SERIAL group
   (one bed at a time), while different token groups AND the no-token pool run in
   PARALLEL. On this repo: `nvidia-gpu` = {check-cachyos-gpu-vm,
   check-selkies-{kde,labwc}-nvidia-vm (exclusive) + check-cachyos-{comfyui,
   unsloth-studio,immich-ml,jupyter-ml}-pod + check-versa-pod (shared)} — ALL
   serial among themselves (an exclusive vfio flip cannot overlap a shared
   nvidia+CDI claim); `test-lock` = {check-preempt-arbiter-pod,
   check-preempt-live-pod, check-cross-pod-cdp} — serial (GPU-free, so parallel
   with the nvidia-gpu group). A read-only GPU DETECTION bed
   (`check-gpu-local`, `charly vm gpu status`) declares NO token → parallel pool.
   The signature that tells the two ceilings apart: `held EXCLUSIVELY … cannot
   share` at the ACQUIRE step (arbiter → serialize the token group) vs `database
   is locked` MID-build (store lock → transient_store). NEVER release a sibling's
   ACTIVE lease to force a parallel claim through — serialize the group instead
   (a stranded lease from a killed claimant is cleared with `charly preempt
   restore`, not by racing it).
4c. **A parallel LONG-bed roster is owned by the persistent session as N
   `run_in_background` tasks — NEVER the sub-agent `/verify-beds` workflow for
   >600s beds.** A sub-agent's internal `charly check run` is ONE foreground call
   (600s-capped), so a VM/GPU bed that outruns 600s is killed mid-run while a
   sub-agent holds it (the "still running when forced to report" incomplete
   verdict — a fan-out artifact, NOT a bed failure). The persistent session
   survives across turns to receive each completion notification, so it is the
   only owner that can hold a long bed (see "Handling a long-running bed"). And
   **NEVER force-terminate a running roster:** SIGKILLing a bed's `charly box
   build` mid-write corrupts the graphroot image (a partial image with a missing
   `manifest` file → every later `podman images` fails exit 125 host-wide);
   recover with `podman rmi -f <corrupt-id>` (the ID the error names). Let a
   roster finish, or tear its deploys down with `charly vm destroy` / `charly
   remove` — transient_store fixes the LOCK, not a hard mid-write kill.
4d. **A shared-tree WALK must tolerate a concurrent sibling's transient build
   artifacts — the FOURTH concurrency ceiling, invisible to every serial run.**
   Beds run in ONE source tree, and a bed that builds in-tree (a candy's makepkg
   under `pkgbuild/{pkg,src}`, a cargo `target/`, an npm `node_modules/`) creates
   directories that are transiently unreadable (fakeroot-owned, mode-0700, or
   half-written) WHILE a SIBLING bed's loader walks the same tree. A walk that
   aborts on the first per-entry `EACCES` fails the sibling's ENTIRE
   `LoadUnified` — surfacing as a bogus downstream error (this campaign: a
   swallowed discover-walk `EACCES` on `candy/examplebuild-localpkg/pkgbuild/pkg`
   became check-local's misleading "unknown kind:local template"). Root-cause
   fix pattern: a tree walk SKIPS an unreadable/erroring subtree (`filepath.
   SkipDir`) and continues — a discoverable manifest can never live in an
   unreadable dir — and skips VCS/build-artifact dirs by name; it NEVER aborts
   the whole load. Same lesson for any shared-state read under concurrency: don't
   swallow the real error (it hides the class), and don't let one sibling's
   transient artifact fail an unrelated bed.
4e. **Per-worktree binaries — bed gates from MULTIPLE branches overlap (PROVEN
   2026-07-12, spikes S0+S0b).** The freshness guard (`main_freshness.go`) compares
   `os.Executable()` against the cwd-walked source root, so a worktree with its own
   `task build:binary` output is SELF-CONSISTENT: `PATH=$PWD/bin:$PATH charly check
   run <bed>` runs the FULL R10 sequence (deploy-add → check-live → fresh update →
   cleanup, external plugins included) on the worktree's binary WITHOUT ever
   installing — `/usr/bin/charly` untouched. Proven concurrently ACROSS worktrees on
   different branches: two DIFFERENT beds (check-substrate 79s inside check-group's
   265s window) from two trees, separate per-tree `.check/`/`.build/` outputs, zero
   cross-contamination, zero leftover deploys. Requirements: the worktree needs the
   `sdk` AND `pkg/arch` submodules inited (`task build:binary` reads
   `pkg/arch/calver.sh`) — but NOT the `box/<distro>` submodules for the ROOT
   disposable roster: root `charly.yml` imports the distro namespaces
   (arch/cachyos/fedora) via remote `@github.com/opencharly/distro-*` refs
   (resolver-fetched into cache, pinned independently of the submodule pointers), so
   the root check beds resolve from local `candy/` layers + registry base images +
   the remote-fetch cache, NEVER the box/* working trees. (A `box/<distro>`'s OWN
   in-submodule beds do need that submodule inited — box-specific work, not the
   cross-cutting root roster a persistent session runs for a core cutover's R10.)
   NEVER `task build:charly` from a worktree (it installs to
   the SHARED `/usr/bin/charly` and yanks every other tree's baseline). Scheduling
   rule when overlapping gates: the SAME bed name must never run twice at the same
   instant (bed→deploy names are deterministic — same `charly-<bed>` names collide);
   distinct beds are collision-free by construction (this section's isolation
   invariants). Cross-gate concurrency shares the ONE store-lock ceiling (item 4)
   and the exclusive-token chains (4b) — one global scheduler, per-bed mutex,
   capacity ≈ the measured maxjobs.
5. **The lead opens the single PR**, gated on the consolidated full final-code
   live test (the beds in parallel); a FRESH `pr-validator` (never a teammate that
   authored code) validates and merges it. Teammates never commit, push, or merge.

Worked partition (illustrative): A→`{check-pod, check-local}`,
B→`{check-jupyter-pod, check-versa-pod}`, C→`{check-k3s-vm}` (VM, needs the
libvirt user session), D→`{check-sway-browser-vnc-pod}` (heavy). All concurrent
→ multiple pods *and* a VM live at once; wall-clock ≈ the slowest chain, not
the sum.

### Agent lifecycle hygiene — stop what you spawned

**The moment an agent's/validator's work is ACCEPTED (verdict delivered, PR merged,
report pasted), STOP it — `TaskStop(<name>)` — which also frees its tmux pane.**
Stale finished agents accumulate silently (one real session leaked 17 idle panes:
pr-validators, guide agents, probes) until teammate spawning itself fails with
"no space for a new pane". When that failure hits, the fix is CLEANUP — sweep with
`tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}
cmd=#{pane_current_command} title=#{pane_title}'` and kill idle agent panes
highest-index-first (never pane .0 of any session) — NEVER a switch away from tmux
teammate mode: the panes ARE the operator's live oversight of every agent, a
standing operator requirement, and `teammateMode` is snapshotted at session start
anyway (a mid-session settings flip does nothing).

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
