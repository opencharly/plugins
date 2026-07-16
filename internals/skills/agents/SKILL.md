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
R10 that has not run, so the fresh validator must reject it. The receiving
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

### Teammate context lifecycle — reuse is TASK-SCOPED, never cross-task

A teammate's accumulated context is an ASSET on its own task chain and a LIABILITY on any
other. The rule: **reuse the live teammate for anything that CONTINUES its assigned unit;
never hand it a different unit — spawn a fresh teammate (and stop the old one), or clear its
context/workspace first, which is the same thing: the new unit starts from zero.**
**STRICTLY ENFORCED (operator directive 2026-07-13): shutdown on task completion is
MANDATORY for teammates AND every other agent (validators, sub-agents) — the moment its
task is done (PR merged / verdict accepted / report delivered), STOP it; EVERY new task
starts a NEW teammate or agent with EMPTY context. There is no related-chain carve-out: a
program of related cutovers is one fresh teammate PER cutover, sequenced by the
orchestrator — never one teammate marching through a queue.**

- **Continue-same-task (REUSE — the loaded context is the point):** a CHANGES-REQUESTED fix
  round on its own PR; the next leg of ITS cutover chain (sdk leg → superproject leg);
  rebase / `update-branch` rounds; an orchestrator-ruled widening or re-scope of the SAME
  unit; the RCA of a failure its own change caused. Respawning for these THROWS AWAY the
  worktree state, scoping map, and bed history the fix round needs, and forces an expensive
  re-derivation.
- **Different-task (NEVER reuse a loaded context — related or not):** the moment its chain
  lands (merged PR + accepted report), a teammate is STOPPED (see "Agent lifecycle
  hygiene"), never re-tasked. A new unit gets a FRESH teammate: stale context anchors the
  new work on the old domain's assumptions, the drained budget double-pays for compactions
  mid-unit, and it surrenders the exact fresh-context benefit delegation exists to provide.
  "Related" does not rescue reuse — a follow-on cutover in the same domain is still a NEW
  task and gets a NEW teammate; the predecessor's knowledge crosses via durable artifacts
  (below), never via a shared context.
- **Sizing at spawn:** an assignment is ONE task — a single atomic cutover, including its
  multi-repo PR legs — sized to one context budget. The orchestrator decomposes a program
  into per-task teammates; it never hands one teammate a queue of units, related or not.
- **Durable artifacts make stopping lossless:** scoping maps, verdict comments, decomposition tables,
  and handoff notes go to FILES (scratchpad or the PR) BEFORE the teammate stops, so a
  successor starts from disk, never from a predecessor's context. Validator variant: a
  validator MAY stay alive between the legs of ONE PR chain when the next leg is imminent;
  otherwise stop it and spawn fresh per leg — the durable PR verdict comment carries the
  coordinates forward.
- **Mid-task context pressure INSIDE a teammate:** compact-and-continue on the SAME task is
  normal; if the remainder is separable, write the handoff package (above) and the
  orchestrator spawns a successor for the remainder — never re-purpose the drained teammate
  for new work.

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

**A parity / golden / coverage instrument is a CLAIM until proven NON-VACUOUS.** When a
teammate offers a byte-parity harness, a golden corpus, or an "N cases pass" table as
evidence, verify the instrument actually EXERCISES what it claims BEFORE the verdict
counts — count the cases it really runs (a golden corpus with ZERO fixtures "passes"
every diff; a parity test whose two sides are the same code path proves nothing). The
motivating incident: a 0-fixture corpus reported green while covering nothing. Read the
instrument's inputs, not just its exit code — a green from an empty or self-referential
instrument is a false pass, exactly the class RDD exists to catch.

### The orchestrator OWNS architectural integrity

**The orchestrator OWNS architectural integrity.** Every placement decision is
judged against the END-STATE architecture (the CLAUDE.md kernel definition —
"Core is a PLUGIN HOST"), never against current constraints alone; an ad-hoc
decision in breach is corrected AT ONCE — never ratified as local pragmatism. A
"stays in core" ruling is valid ONLY with a named K-wave exit and a tracked task;
a constraint blocking the right placement gets a constraint-REMOVAL task — the
decision never silently conforms to it. On every merge, the delta re-gate includes
an ARCHITECTURE delta (core LOC down, or flat with a named tracked reason). The
enforcement layers are ONE stack, named together so no future session rebuilds
them piecemeal: **the pre-commit hook (commit-time no-new-alias / no-new-kit-import
block) → the `pr-validator` ARCHITECTURE GATE (the no-new-breach placement review +
the explicit `placement:` verdict) → the P16 triple gate (the end-state floor:
allowlist + import-purity + zero-alias) → the orchestrator's every-decision
judgment (this duty).**

### The north-star protocol — align a multi-teammate program BY CONSTRUCTION

Before fanning a multi-teammate program out, the orchestrator AUTHORS a
**NORTH-STAR document** and hands it to every teammate. Scoped executors cannot
make whole-board decisions — each sees ONE cutover, never the destination — so
program alignment is achieved BY CONSTRUCTION: the document PRE-ANSWERS the common
hard calls, STOP-and-ask covers the novel ones, and the orchestrator verifies
every checkpoint regardless ("The orchestrator RDDs every decision", above). The
document has four parts, all present-tense and CONCRETE:

- **(a) The concrete END-STATE** — tables + end-state call paths, NEVER
  aspirations. "What the system IS when we're done" and "how it WORKS when we're
  done", spelled precisely enough that a teammate can check its own output against
  it.
- **(b) ORDERED decision heuristics** for the hard calls teammates will hit,
  applied IN ORDER (this is the canonical SHAPE; the orchestrator fills in the
  program's specifics): *does my move need a NEW seam? → almost certainly wrong;
  check whether the program's shared data spine already covers it, and if it does
  not YET, register the IOU + STOP-and-ask — never build a seam a later wave
  deletes (R3-across-time)*; *does my move need types the destination forbids? →
  the move WAITS for the enabler; register the IOU (size + enabler) — never churn
  call sites to fake it, never move the type across the boundary, never alias*;
  *bodies move, shells follow*; *placement by DOMAIN, not by filename*; *when in
  doubt → STOP-and-ask*.
- **(c) The OBSERVED ANTI-PATTERNS list** — every mis-step already caught, named
  so it is not repeated; the orchestrator APPENDS to it as new incidents surface.
- **(d) The current MEASURED state** — the program's tracked metric as last
  measured, updated at EVERY merge (per-merge measurement, below).

**The document is BINDING and travels with every spawn.** EVERY spawn brief names
the north-star BY PATH; a teammate that hits a **task-vs-north-star conflict STOPS
and asks the orchestrator** — never a local resolution, never a silent absorption,
never an improvised seam. A wrong local decision costs one correction round; a
silent one costs the program its goal.

**Companion instrument — the IOU REGISTER.** Every deferred item ("do X until wave
N") is a registered ENTRY carrying three fields: its SIZE, the ENABLER that must
become true before it can be collected, and the WAVE that delivers that enabler.
**No wave closes while it holds an UNREGISTERED IOU**, and the NEXT wave's plan is
built FROM the register, not from memory — so nothing deferred is silently dropped
and every "later" has a named owner. (This is the whole-program form of R2's
no-follow-up-someday: a deferral is legal only as a registered, wave-owned entry.)

**Companion instrument — PER-MERGE MEASUREMENT.** At every merge the orchestrator
measures the program's tracked metric (LOC for a relocation program, coverage for
a test push — whatever the program optimizes) against the plan's projection. A
variance past the threshold (>20%) is NOT absorbed — it is EXPLAINED, and the
residual is REASSIGNED to a NAMED wave, never silently eroded; that is what keeps
the (d) measured-state line honest. Its sharpest single check is the
**measured-delta rule: a relocation whose measured delta is dispatch-SHELLS while
the ENGINE stays behind a reentry seam is REJECTED at orchestrator review — bodies
move, shells follow.** A shells-only move books no real progress toward the
end-state, however large the raw diff looks.

### Migration-ledger discipline — measured maps, surface-named enablers, variance = incident

A long migration's LOC ledger / IOU register is a CLAIMS TABLE, and four proven failure
modes govern it (all observed live in one program):

- **Rows are CONFLATED-UNTIL-MEASURED.** A register row authored from file-LOC sums
  overstates collectibility (enabler gaps hide inside "residue") AND understates body
  depth (call-graph reads reveal deep orchestrations) — measured variances of −79%,
  −45%, ~−80%, and +60% landed in four consecutive scoping rounds of one program. No cut
  proceeds from a register estimate: a SCOPING MAP (per-file measured LOC +
  MOVE/STAY/DIE/SHARED verdicts + call-graph reads in BOTH directions — OUTBOUND
  enabler-fit, the fields the unit reads vs what the enabler actually carries, and
  INBOUND footprint, the transitive callee stack the body drags along — file:line
  cited) precedes every cut, and the orchestrator re-verifies its load-bearing claims.
  **A body's file-LOC is a FLOOR for the move, never the move**: outbound gaps
  over-count collectibility (one-signed +, the enabler's surface is a subset of the
  owned surface) and inbound drag under-counts move size (one-signed −, file-LOC
  excludes callees) — the same estimator defect with opposite signs; size every row by
  its call-graph, both directions, never by its file-LOC.
  This is an AUTHORING rule, not a retrospective diagnosis: a row quotes NO collectible
  LOC until its per-file boundary-law decomposition exists — owner-sums can only
  over-count collectibility, so an undecomposed row is UNMEASURED by definition.
- **An enabler is named by its exact SURFACE, never a subsystem word.** "The envelope"
  as an enabler let rows gate on a def that deliberately excluded what they needed —
  while the caveat sat in the SAME document without propagating. A row's enabler names
  the def/fields/op it consumes; when an enabler LANDS, every row naming it is
  RE-AUDITED against the actually-landed surface.
- **Every plan-vs-measured mismatch is a BLOCKING INCIDENT** — a dedicated
  root-cause-analyzer RCA, never a per-row hand-wave ("the register conflated…" is a
  finding, not an RCA).
- **Same-signed variance recurring across ≥2 rounds is a systemic ESTIMATOR defect** —
  it triggers a dedicated root-cause-analyzer RCA on the estimating METHOD itself, never
  another per-row reassignment. (The per-merge ">20% = explain + reassign" rule handles
  ONE variance at merge time and structurally cannot see a series — a real program ran
  three same-signed rounds before escalating; the RCA found every applied remediation
  was data-level while the authoring method stayed broken.)
- **A gap discovered inside an assigned cutover means BUILD THE ENABLER IN THE CUTOVER**
  (spike-first; the growth lands WITH its consumers) — never a clean-slice landing plus
  deferral, which is the micro-PR fragmentation pattern operators reject. Scope
  exclusions exist only as per-file boundary-law justifications (E/M/B/D) the
  orchestrator personally reviews.

### Crossed-ruling reconciliation — one unambiguous instruction beats several partial ones

Orchestrator rulings and teammate checkpoints CROSS IN FLIGHT: a ruling sent while a
teammate's report is already in transit lands as a second, apparently-conflicting
instruction. So when issuing a ruling that MAY cross an in-flight report, the
orchestrator's NEXT message EXPLICITLY reconciles both states — naming which stands
and which is superseded ("my X is superseded by your finding; your Y still applies" /
"my X stands; revert your Y"). An unreconciled PAIR of partial rulings is the failure
mode: a teammate unable to tell which wins may REVERT already-R10-gated work to satisfy
the older instruction. One unambiguous instruction always beats several partial ones. A
teammate that receives apparently-conflicting rulings STOPS AND ASKS the orchestrator
rather than picking one (the north-star "when in doubt → STOP-and-ask" heuristic applied
to rulings).

### The responsibility matrix — who owns what (no ambiguity)

**ORCHESTRATOR** (the persistent main session, ×1, most-capable model):
- OWNS: **architectural integrity** (every placement judged against the end-state;
  breaches corrected AT ONCE); the plan/contract + ALL scope rulings (every
  STOP-and-ask terminates here); **independent RDD-verification of every teammate
  decision** (bidirectional — never rubber-stamps, and is never rubber-stamped);
  **ALL full bed runs / R10 rosters** (`run_in_background`; only the persistent
  session survives to receive completion notifications); parity re-derivations;
  **validator routing + post-merge verification** (tag-verify, main ff, the delta
  re-gate INCLUDING the architecture delta); merge sequencing + rebase broadcasts;
  the task board; **the THEMATIC BATCH QUEUES** (the Cutover Sizing Law,
  `/charly-internals:cutover-policy` "Cutover sizing — the batch law": every
  non-blocking fix is routed into a named batch with an owner and a start — a
  teammate brief for a small fix NAMES its batch; a solo landing ceremony for a
  small non-blocking fix is a routing error the orchestrator corrects); agent/
  worktree lifecycle (spawn, stop-stale, prune, the slot budget); operator
  escalation.
- NEVER: authors cutover code it then validates; grinds mechanical bulk itself
  (delegates); lets a "stays in core" ruling stand without a K-wave exit + tracked
  task.

**IMPLEMENTATION TEAMMATE** (×N cost-scaled, ONE per independent cutover, one
worktree each):
- OWNS: its ONE cutover end-to-end — design within the contract, implementation,
  unit gates (build/test/lint/gofmt/cue-gen-repro), SHORT foreground checks
  (`charly box validate` / `charly check box`), R5 sweeps, ADE plans, CHANGELOGs,
  **authoring** its PRs, fix-rounds IN-PLACE on CHANGES-REQUESTED, handoff packages
  when context runs short.
- DELEGATES: mechanical bulk to transient sub-agents it briefs AND reviews (never
  rubber-stamps).
- NEVER: runs a full `charly check run` / any bed roster (the orchestrator's);
  merges or validates its own PR; edits outside its worktree; touches a FROZEN tree
  (message-first on any discovery); changes contract scope unilaterally; spawns
  persistent teammates.

**PR VALIDATOR** (fresh context, one per cutover CHAIN — sdk→plugins→super in one
session):
- OWNS: independent adversarial re-validation (R0–R10 + skills + **the ARCHITECTURE
  GATE placement review with the explicit `placement:` verdict**); the squash-merge;
  the merge-time CalVer; **the tag on EVERY repo** (a skipped tag is a defect); the
  durable PR verdict comment BEFORE any gated action.
- NEVER: validates anything it authored; `--admin`/force; close-and-recreate; skips
  the placement verdict.

**TRANSIENT SUB-AGENT** (spawned by anyone; frees its slot on return):
- OWNS: one bounded, file-disjoint unit (relocation batch / survey / spike / golden
  harness) + its own unit verification; returns VERBATIM results to its spawner.
- NEVER: full beds; commits/pushes/PRs; scope decisions; work beyond its brief.

**DESIGN RESERVE** (a former implementer kept addressable for keystone questions):
- OWNS: answering design questions from its deep context. STOPPED once its knowledge
  is durably captured (handoff docs) — persistent slots belong to cutovers.

**Tie-breakers:** ambiguity about ownership → the orchestrator rules. Beds → ALWAYS
the orchestrator. Merges/tags → ALWAYS a validator. Code → ALWAYS a
teammate/sub-agent worktree. Scope → ALWAYS the contract + the orchestrator, never a
lane-local decision.

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
  R0–R10 + the relevant skills, posts the `charly/pr-validator` commit status,
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
  `check-android-emulator-pod` / …). Distinct beds get distinct `charly-<bed>`
  container/VM/domain names, and a bed run tags every fixture IMAGE it builds with
  a per-run `<bed-root>-<runCalver>` tag (#75), so two beds building the SAME
  fixture image NAME never race the store-global tag namespace; the author assigns
  each disjoint host ports too (the loader does NOT check ports — an overlap fails
  the second bed at deploy), so they run concurrently and safely.
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
  file** (no shared-file edits), and the one shared tree's **`charly` binary rebuild
  is a single barrier** between the parallel-implement and parallel-bed-R10 phases.
  Canonical shape: `Core (seq) → Implement (parallel by bed) → Integrate+build
  (seq barrier) → BedR10 (parallel by bed) → Review (parallel, read-only,
  optional)`. **The barrier is load-bearing because `charly` enforces a stale-binary
  freshness guard** — it refuses heavy ops (`image build`, `deploy add`) whenever
  any `charly/*.go` source is newer than the INVOKED binary (remediation: ONE `task
  build:binary` in the shared checkout). A teammate editing `charly/*.go` WHILE
  another's bed is mid-run trips that guard on the bed's deploy step, so rebuild
  ONCE at the barrier, then run every bed against the now-stable binary. **The
  barrier carries a bare-`$PATH` caveat**: the shared tree's bed set must actually
  invoke `./bin/charly` (explicitly, or with the shared tree's `bin/` prepended
  onto `$PATH` for the bed's session) — a bed that shells to bare `charly`
  otherwise resolves whatever the HOST has installed, never the shared tree's
  freshly-rebuilt binary (the SAME trap "Host-local beds are NEVER a worktree
  gate" describes below). **This barrier binds the SHARED-TREE model ONLY** (one
  checkout, one binary) — a MULTI-WORKTREE team needs no barrier at all, since
  each worktree's own `bin/charly` is self-consistently gated; see "The charly
  binary in a multi-teammate / multi-worktree setup" below — never conflate the
  two models.
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
**Scope-of-validity (2026-07-13 live datapoint):** that denial reproduces only when no
USER/MANAGED-level grant covers the action — user-level settings (`~/.claude/settings.json`,
e.g. an operator `autoMode.allow` rule) resolve INDEPENDENTLY of project root, and a
submodule-rooted validator under such a rule posted `success` AND merged with zero denials.
Superproject rooting REMAINS the rule (project-level `permissions.allow`, the CLAUDE.md
hierarchy, and transcript determinism are all root-dependent) — but diagnose a denial by
checking BOTH settings layers, never root alone.
Rooting fixes the STATUS POST (cleared by `permissions.allow`). **The MERGE is a
SEPARATE, stricter classifier gate — Merge-Without-Review — that `permissions.allow`
does NOT clear** (proven: `gh pr merge` denied for BOTH a superproject-rooted sub-agent
AND the main session despite the rule); it lands only under the operator's `autoMode.allow`
rule (user/managed settings) or fresh in-context user consent, never CLAUDE.md prose. See
`/charly-internals:git-workflow` B5.

**2. A permission denial ENDS the sub-agent's turn — record the verdict durably
FIRST.** The denial text instructs the agent to "STOP and explain to the user", and it
stops; its explanation never reaches the spawning session (observed repeatedly: agents
idle "available" with no report). So every agent that will attempt a permission-gated
action MUST, before attempting it, put its full verdict in its workflow's durable channel.
A `pr-validator` posts its PR comment before the gated action; posting a **`failure`**
status or a comment is NEVER gated — Self-Approval only blocks marking a check **passed**
— so a FAIL verdict is always deliverable. Then it records the verbatim outcome in that
same durable channel.

**3. Reconnect via durable state; never wait on the message channel.** The truth is in
the workflow's durable records and API state: for a validator, the PR's statuses +
comments; for a bed, Charly's summary; and the agent's completion result. To WAIT on a condition,
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

**5. A teammate IDLE notification is turn-boundary noise, not proof it died or stalled.**
The harness emits an idle signal every time a teammate YIELDS its turn — which a working
teammate does constantly (between tool batches, at every checkpoint). Treating the first
idle as "went silent" and nudging or replacing on it is a false-positive that discards
live work. Before nudging or escalating, CONFIRM real inactivity from durable state:
`find <teammate-worktree> -newermt '-15 min'` (any file touched recently → it is working),
its `git status` dirty-count moving, or its transcript growing. Only a teammate with NO
worktree activity across a real window AND no checkpoint is genuinely wedged — the
nudge-then-replace reflex is correct ONLY after that confirmation.

**6. Confirm a background child's TERMINAL state from its completion signal before
respawning — never from its output-file size.** A bash `run_in_background` child of a
TEAMMATE is harness-REAPED when that teammate yields its turn (the motivating incident:
the children were killed 9s and 47s after the teammate's idles, while the identical
command run in the FOREGROUND passed). So a teammate runs any owned work it needs to
completion SYNCHRONOUSLY (foreground), and hands a bed or any other turn-outliving job to
the PERSISTENT session (see "The binding rule" below); it never leaves a bg child to
finish after it yields. An `Agent`-tool child MAY survive the parent's yields, but its
terminal state is authoritative ONLY from its COMPLETION signal (the `<task-notification>`
/ exit code / durable workflow record), NEVER from the size or tail of its output file (a
half-written log is indistinguishable from a reaped one). Respawn only after the
completion signal confirms the child actually ended.

**7. Validator evidence discipline — six lessons proven this session, each a
real validation-round finding, not a hypothetical.**
- **Cross-repo PR/issue citations in ANY CHANGELOG entry or PR body MUST carry
  the owner/repo qualifier** — a bare `#N` is ambiguous the moment it's read
  from a different repo than the one it names (proven: a plugins CHANGELOG's
  unqualified "PR #126" was flagged as a fabricated citation in PR #70's
  round-1 validation, because the validator checked the wrong repo first;
  qualify every cross-repo reference as `owner/repo#N`, e.g.
  `opencharly/charly#126`).
- **The repo set a citation check must search is `opencharly/{charly,
  plugins, sdk, distro-*, pkg-*, .github}`** — checking only the repo the
  CHANGELOG lives in (or guessing a plausible-sounding repo name) is how a
  real citation gets misdiagnosed as fabricated.
- **A validator (or any agent) verifying a claim against a LOCAL checkout
  (e.g. `/home/atrawog/Atrapub/o/charly`) must treat that checkout as
  POTENTIALLY STALE and check `origin/main` directly** — three independent
  validators this session hit exactly this trap, verifying a claim against a
  local tree that had already fallen behind the remote.
- **Every evidence attestation (a grep count, a checklist line, a balance
  check) pasted into a PR body or CHANGELOG MUST be RE-RUN at the FINAL head
  immediately before pasting — never transcribed from memory or an earlier
  run.** This is the SAME failure class in two independently-hit incidents
  (PR #70's Finding B — a fabricated grep count that didn't reproduce; a
  parallel sdk-repo validator round hitting the identical mistake) —
  evidence a reader can't verify because it was never actually re-executed
  is a fabrication, however unintentional.
- **A `git fetch`/`git push` error naming a MISSING remote ref on a branch
  you believe EXISTS is a STOP-and-investigate signal, not a
  nothing-to-reconcile signal.** The branch's state changed out from under
  you — a squash-merge-then-delete is the common cause — and pushing anyway
  silently recreates an orphan branch of the same name, detached from
  whatever PR it used to belong to. Re-derive the real state (`gh pr view
  <n> --json state,mergedAt`) BEFORE pushing again. Proven live this
  session: exactly this sequence recreated a deleted post-merge branch.
- **A validation clone's working tree can carry STALE STAGED CONTENT from
  `git checkout <ref> -- .`** (this form copies file CONTENTS from `<ref>`
  into the working tree/index WITHOUT moving HEAD or the branch pointer,
  unlike `git checkout <ref>` / `git switch <ref>`) — a subsequent `git
  switch --detach` then REFUSES (uncommitted changes would be overwritten),
  which is the detection signal, not a tool malfunction to route around.
  **The recovery is a hard reset of the DISPOSABLE clone** — it exists only
  for this validation run, so discard it (or `git reset --hard` +
  `git clean -fdx` to the intended ref) rather than reconciling file-by-file
  — **followed by a FULL re-verification**, never a partial patch-up: a
  working tree that silently absorbed foreign content cannot be trusted to
  be clean anywhere else in it either. Proven live during a validator run
  this session.

**8. Orchestrator PR ledger + coordination-comment duty.** The orchestrator
maintains a PR LEDGER — every session-created PR is tracked to an explicit
disposition (merge after validation / close with a pointer rationale / hand
off to another owner) — no orphans. On every `main` advance, the ledger's
still-open entries are re-checked for staleness (a merge, a superseding
rename, a policy change that invalidates one of their hunks). **When ANY
session's work creates a KNOWN interaction with a PR it does not own —
including a PR explicitly OUT OF that session's scope by operator directive —
it posts a COORDINATION COMMENT on that PR rather than staying silent:
commenting is ALWAYS in scope even when evaluating or merging is not.** Worked
precedent (this session): coordination comments landed on three
sibling-session PRs while their evaluation and merge stayed with their own
owners — `opencharly/charly#130` (a loader-file conflict warning ahead of a
wave merge), `opencharly/plugins#73` (a same-file docs-batch rebase warning),
and `opencharly/charly#112` (a rescue-history + coming-staleness note). See
`plugins/internals/agents/pr-validator.md` "Cross-PR awareness" for the
matching per-PR-validation-run duty — that spec owns the PR-VALIDATOR's own
sweep-and-comment mechanics; this item owns the ORCHESTRATOR's standing
ledger discipline across the whole session, never restated here.

## The charly binary in a multi-teammate / multi-worktree setup

Every teammate/worktree in a multi-agent run needs its OWN charly binary — conflating
the host binary with a worktree's own build is the single most common way an
in-flight cutover leaks onto shared host state. This section is the canonical
reference; `/charly-internals:git-workflow` and `/charly-internals:go` point here
rather than restate it.

- **Two binaries, two roles.** Per-worktree `bin/charly` — built via `task
  build:binary` (the `binary:` Taskfile task: a CalVer-stamped build + a
  `candy/charly/bin/charly` copy, gitignored, NO install step) — is THE dev binary:
  **every teammate uses its OWN worktree's `./bin/charly` for every charly verb** —
  build, validate, check run, everything. The HOST-INSTALLED `charly` is a
  DISTRO-NATIVE PACKAGE (`.pkg.tar.zst`/`.rpm`/`.deb`, built via `task
  pkg:arch`/`pkg:fedora`/`pkg:debian`/`pkg:all` into `dist/`, or downloaded as a
  published release) installed with the DISTRO's OWN package manager (`pacman
  -U`/`dnf install`/`apt install`) — this is the ONLY canonical host-refresh path;
  the system-wide auto-install machinery (the former `charly`/`install`/
  `install-arch` Taskfile tasks) is REMOVED. (`task install-portable` — a portable
  `$HOME/.local/bin/charly` copy — remains in the Taskfile for solo bootstrap, but
  it writes to a host location exactly like a package install, so the SAME
  in-flight-work boundary below applies to it too — it is not a multi-teammate
  dev-loop shortcut either.)
- **The host-install boundary — no host-writing target runs during in-flight
  multi-teammate work, period.** Neither the package-manager install NOR `task
  install-portable` is ever invoked while teammates are mid-cutover: both write to
  host state (`$PATH` or `$HOME`) every concurrent teammate may resolve, and either
  would publish an UNMERGED branch's binary where a sibling teammate or the
  operator expects `main`'s behavior — an R9 violation. The motivating incident
  that hardened this rule: a teammate's worktree smoke bed (`check-commands-local`,
  a HOST-LOCAL bed — next bullet) tripped the stale-binary guard, and the teammate
  "fixed" it by running the (now-removed) system-wide install task — publishing an
  unmerged branch's binary onto the host. The host is updated from MERGED `main`
  ONLY, post-landing, by the orchestrator/operator, ONE writer at a time (see
  "Post-merge resync" below).
- **Stale-binary guard semantics are PER TREE.** `CheckBinaryFreshness`
  (`charly/main_freshness.go`) walks UP from cwd to find the opencharly source root
  (the dir containing BOTH `charly/main.go` and `charly.yml`), stats the INVOKED
  binary via `os.Executable()`, and compares it against the newest `.go` mtime under
  `<root>/charly/` (60s slack; info-only verbs — version/help/status/inspect/list —
  are exempt). This is entirely SELF-CONSISTENT per worktree: a guard trip while
  running `./bin/charly` inside YOUR OWN worktree means YOUR `bin/charly` is older
  than your own edits — the fix is `task build:binary`, never a host install (a
  host write is off-limits during in-flight work regardless, per the boundary
  above). A guard trip that resolves to the host-installed `charly`
  means you are on the WRONG PATH (your worktree's `./bin` isn't ahead of it on
  `$PATH`) or running the WRONG BED CLASS (next bullet).
- **Host-local beds are NEVER a worktree gate.** A `local: {host: local}` deploy (or
  a bed with a nested `local:` member) shells out to bare `charly` on `$PATH` — that
  resolves whatever the HOST has installed (the native package, if any is present),
  NOT your worktree's `./bin/charly`, regardless of which worktree you're standing
  in. Such a bed can only ever exercise HOST state — never your worktree's in-flight
  source. In a worktree context, pick a pod or VM bed instead: a pod bed bakes the
  worktree's binary via `--dev-local-pkg`; a VM bed stages the worktree `charly`
  into the guest over `kit.EnsureCharlyInGuest`. A guard trip (or any surprising
  behavior) on a host-local bed while doing worktree work means you picked the
  WRONG BED CLASS — never a signal to install anything. (Consistent with
  `/verify-beds`'s blanket REFUSAL of host-local beds, motivated there by
  workstation safety — applying candies to the operator's own machine — see "The
  shipped workflows" above; this bare-`$PATH` resolution is the SAME caveat the
  shared-tree barrier below has to account for.)
- **Invoking `./bin/charly` directly is NOT sufficient for beds whose plan steps
  shell out to bare `charly`.** The OUTER invocation's binary does NOT propagate to
  an INNER bare-`charly` subprocess a bed's own `command:` plan step launches —
  only a `$PATH` prefix does. Always run a bed as `PATH=$PWD/bin:$PATH ./bin/charly
  check run <bed>` (the form "Per-worktree binaries" (4e) below already
  recommends), so every internal subprocess resolves the worktree binary
  consistently, not just the command you typed. **The failure signature:** a
  SINGLE stale-binary step failure deep inside an otherwise-green run — often on a
  step testing a surface UNRELATED to your actual change, after minutes of
  progress — is the tell that an inner bare-`charly` call resolved the host
  binary instead of yours; the guard is reporting a REAL staleness, just for a
  hidden invocation you didn't prefix.
- **Multi-worktree concurrency corollary.** Because each worktree carries its OWN
  binary and its OWN freshness-guard scope, teammates working in DISTINCT worktrees
  need NO freeze barrier between them — each rebuilds its own `./bin/charly` via
  `task build:binary` whenever it likes, with zero cross-teammate interference. The
  "freeze `charly/*.go` + ONE `task build:binary` at the barrier" rule
  ("Implementation workflows are bed-scoped too" above, and
  `/charly-internals:git-workflow` B3) applies ONLY to the SHARED-TREE team model —
  multiple agents editing ONE checkout with ONE shared binary, where the barrier
  ALSO carries a bare-`$PATH` caveat: the shared tree's bed set must invoke
  `./bin/charly` explicitly (or prepend the shared tree's `bin/` onto `$PATH` for
  the bed's session) — a bed shelling to bare `charly` otherwise resolves whatever
  the HOST has installed, the SAME trap as the host-local-beds bullet above, not
  the shared tree's freshly-built binary. The two models are NOT interchangeable: a
  shared-tree team needs the freeze because there is exactly one binary every bed
  run depends on; a multi-worktree team needs no freeze because there is one binary
  PER worktree. See "Per-worktree binaries" (4e) below for the concurrent-worktree
  bed-proof detail.
- **Within-worktree self-freeze — the COMPLEMENTARY rule.** The per-tree freshness
  guard does not check only at the start of a bed run — it compares the invoked
  binary against the cwd's sources at EVERY heavy verb the bed executes, mid-run. So
  editing your OWN worktree's `charly/*.go` — even a comment-only edit — WHILE YOUR
  OWN bed is mid-flight trips the guard on the bed's NEXT step and fails an
  otherwise-green run. The two freeze scopes are complementary, not the same rule:
  (a) ACROSS distinct worktrees, no barrier is needed (the corollary above — each
  worktree's binary is independent); (b) WITHIN one worktree, freeze YOUR OWN
  `charly/*.go` for the duration of YOUR OWN bed run — queue edits until the verdict
  lands, then `task build:binary` + re-run. The failure is SELF-INFLICTED, not a
  product defect: RCA it as "I edited mid-run" (a stale-source hit citing a file you
  just touched), rebuild, and re-run fresh — never chase the guard as a bug.
- **Side-effects (documented elsewhere — pointers, not copies).** `task
  build:binary` keeps the dual path `bin/charly` ↔ `candy/charly/bin/charly` in
  sync (a manual `go build -o` does not) — see `/charly-internals:go` "Quick
  Reference" / "Debug a Build Issue" + `/charly-tools:charly`. It does NOT touch
  the tracked `pkg/arch/PKGBUILD` — that file is read only by the distro-native
  package build (`charly box pkg`, run inside a container from its own embedded
  template), never by a bare-host `go build`.
- **Post-merge resync.** After a wave lands, the orchestrator/operator updates the
  HOST package from the new `main` via the native-package path — build a fresh
  release artifact (`task pkg:arch`/`pkg:fedora`/`pkg:debian` into `dist/`, from the
  MAIN checkout) and install it with the distro's package manager, or install a
  newly published release — NEVER via a Taskfile target that installs directly.
  Each long-lived worktree is then either removed (its cutover is done) or
  fast-forwarded to the new `main` + `task build:binary` re-run before reuse — never
  left pointing at a pre-merge binary while its worktree source has moved on.

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
- **DECLARE an intended live bed run to the orchestrator and wait for a slot.** Any agent
  about to run a real `charly check run <bed>` / `charly update` first announces it and
  waits to be scheduled — the orchestrator owns bed serialization (the per-exclusive-token
  groups, and host build/store capacity). A bed launched without declaring it races an
  already-running roster (the bed-mutex incident); the live-bed schedule is the
  orchestrator's, never the individual agent's. (Shared FIXTURE images no longer need a
  mutex — bed runs tag them per-run `<bed-root>-<runCalver>`, collision-free by
  construction; `/charly-check:check`.)
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
   reminders, NOT copies: a trigger never restates the rule BODY. Claude hooks
   point to `CLAUDE.md`; Codex follows its complete `AGENTS.md` rulebook.
2. **Deterministic `PreToolUse` gates** that cover immediate command mechanics
   only: hook bypass (`--no-verify` / `-n` / `core.hooksPath`), untokenizable
   commit commands, configured Go lint for staged Go modules, force-push, and a
   direct push to `main`. Attribution identity/confidence, change class,
   CHANGELOG coverage, architecture, and R0–R10 evidence belong exclusively to
   the fresh `pr-validator`; the hook contains no duplicate policy regexes.

The honest division of labor: **hooks guard command mechanics; agents judge
policy and proof.** Never re-bloat a hook or reminder into a second copy of
CLAUDE.md or validator logic — name + point, never restate.

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
container / libvirt-domain names — a `vm:` bed's libvirt domain is keyed by the DEPLOY name
(`vmDomainIdentity`), NOT the shared `kind:vm` entity it references, so sibling beds on ONE entity
(`vm: {from: eval-vm}`) still get distinct `charly-<bed>` domains + per-deploy disk overlays (P33).
The FIXTURE IMAGES a bed builds are isolated the same way — by a per-run TAG, not a name: a bed run
tags every image it builds (`charly box build … --tag <bed-root>-<runCalver>`) and passes that tag on
every deploy step (`bedRunImageTag`, the tag analogue of `vmDomainIdentity`), so two beds building the
SAME fixture image NAME (e.g. `check-sidecar-pod` + `check-k8s-deploy` both building
`check-k8s-deploy-app`) no longer race the store-global short-name→newest-local-CalVer resolution —
the last-write-wins collision #75 fixed (the pre-#75 "collision-free by construction" claim was
FALSIFIED for beds sharing a fixture image name).
**Host-port disjointness is NOT
statically guaranteed, so EVERY eval bed MUST use PORT AUTO-ALLOCATION — never a
hardcoded host port.** The loader checks no ports, so a hardcoded host port
shared by two beds surfaces only at deploy time when `CheckPortAvailability` /
passt's `Listen failed … Address already in use` fails the SECOND bed's `start`
(a real concurrency defect this campaign hit: two VM beds both pinned SSH host
`12227`). Manual "pick disjoint ports" deconfliction is FORBIDDEN — it is
fragile authoring that silently collides the moment a bed is added or the roster
runs concurrently. Use auto-allocation BY CONSTRUCTION: a `vm:` bed sets
`ssh: {port_auto: true}` (the runner probes a free host port and persists it in
`vm_state`) AND an extra `network.port_forwards` entry uses the `auto:<guest>`
sentinel (same mechanism — the host port auto-allocated + persisted, resolved into
the render + the k3s kubeconfig rewrite; NEVER a hardcoded `<host>:<guest>` shared
across beds — the 16443 collision the k3s-vm pair hit); a `pod:`/`local:` deploy
uses the `port: [auto]` sentinel
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
   ephemeral eval host. Complementary hygiene (R44 Option A): `charly check box` runs its
   probes in ONE persistent container (`podman exec` per step, not `podman run --rm` per
   step), minimizing the container-setup store race; a residual setup failure is classified
   INFRA.
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
   2026-07-12, spikes S0+S0b).** See "The charly binary in a multi-teammate /
   multi-worktree setup" above for the canonical host-vs-worktree-binary rule; this
   item adds the concurrent-bed proof + the CalVer-stamping detail. The freshness
   guard (`main_freshness.go`) compares
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
   NEVER install to the host from a worktree — the host-install boundary above is
   ABSOLUTE, and no `task` target does it anyway. **The per-worktree binary MUST be
   CalVer-STAMPED** — build it with `task build:binary`,
   which passes `-ldflags "-X main.BuildCalVer=<calver>"`; a bare `go build -o`
   yields an UNSTAMPED binary that reports version `unknown` and FAILS every bed step
   asserting the CalVer stamp (a `vm:` bed pushes the host binary INTO the guest and
   asserts `charly version` there, so an unstamped binary fails the guest witness).
   **This trap has RECURRED — `task build:binary` (never a bare `go build -o`) is the ONLY
   sanctioned way to produce a per-worktree binary; a plain `go build` is a silent gate
   defect that surfaces only at the guest stamp assertion, deep into a long VM bed.**
   Scheduling
   rule when overlapping gates: the SAME bed name must never run twice at the same
   instant (bed→deploy names are deterministic — same `charly-<bed>` names collide);
   distinct beds are collision-free by construction — their `charly-<bed>` deploy
   names AND (post-#75) the FIXTURE IMAGES they build, which a bed run tags per-run
   `<bed-root>-<runCalver>` so two beds building the same fixture image name never
   race the store-global tag namespace (this section's isolation invariants); and
   **verify every bed NAME against the LIVE tree roster**
   (`grep '^check-.*:' charly.yml`) BEFORE each launch — rosters change across
   cutovers, so a stale name from notes or memory aborts the run. Cross-gate
   concurrency shares the ONE store-lock ceiling (item 4)
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
**A `shutdown_request` MESSAGE is NOT a stop** — it only ends the agent's conversation;
the process and its pane persist until `TaskStop`. Message-then-stop is courtesy;
message-INSTEAD-of-stop is the leak (a real session accumulated 8 finished wave-teammates
idling for hours this way). Fire `TaskStop` the moment the work is accepted — every agent,
every validator, no exceptions.
Stale finished agents accumulate silently (one real session leaked 17 idle panes:
pr-validators, guide agents, probes) until teammate spawning itself fails with
"no space for a new pane". When that failure hits, the fix is CLEANUP — sweep with
`tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}
cmd=#{pane_current_command} title=#{pane_title}'` and kill idle agent panes
highest-index-first (never pane .0 of any session) — NEVER a switch away from tmux
teammate mode: the panes ARE the operator's live oversight of every agent, a
standing operator requirement, and `teammateMode` is snapshotted at session start
anyway (a mid-session settings flip does nothing). Stopping is also the REUSE
boundary: a landed teammate is never re-tasked with a different unit — see
"Teammate context lifecycle" above.

**Stop ONLY your own children, by task id — NEVER pattern-kill by name.** `pgrep -f
<substring>` / `pkill -f <substring>` matches EVERY process whose argv contains the
substring, regardless of owner — so a `pkill -f 'charly check run'` from one agent kills
another agent's (or the operator's) live bed, and a `pkill -f charly` is catastrophic
(PID-confirmed cross-kill incident: a substring match reaped a sibling's running roster).
Terminate a child you own with `TaskStop(<name>)` (agents) or the exact task id of the
`run_in_background` job you launched (bash children) — never a name substring. When a
genuinely orphaned resource must be cleared, target it by its specific identity
(`charly vm destroy <entity> --domain <bed>`, `charly remove <name>`, `podman rmi -f
<id>`), never a broad `pkill`.

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
