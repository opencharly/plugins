---
name: strict-policy
description: |
  Operationalization of CLAUDE.md R1-R5 plus the RDD and ADE pillars — the
  engineering-discipline rules that come BEFORE runtime verification.
  Covers: (R1) RCA on every failure via /charly-internals:root-cause-analyzer;
  (RDD) prove every HIGH-RISK assumption on a disposable bed BEFORE editing;
  (ADE) the spec-is-the-test `plan:` acceptance discipline; (R2) no
  "pre-existing" / "out of scope" / "follow-up PR" classifications; (R3) no
  code duplication, generic over ad-hoc; (R4) no ad-hoc workarounds; (R5)
  hard cutover deletes the deprecated path AND every stale reference in the
  same commit.
  MUST be invoked when a failure / warning / anomaly surfaces, when a plan
  rests on a high-risk unproven assumption, when a pattern is about to land
  in a second surface, when a sleep / retry / magic-number is tempting, or
  when a cutover commit is about to ship.
---

# strict-policy — operationalizing R1–R5

## Overview

R1–R5 in CLAUDE.md are the **engineering-discipline gate**. They sit ABOVE the runtime-verification rules R6–R9 and ABOVE the final acceptance gate R10. The order is deliberate: discipline failures are what produce the runtime failures that R6–R9 catch — so the rules that prevent discipline failures must come first.

This skill is the operational reference for R1–R5. Each section below restates the rule, lists what it forbids precisely, lists what it permits, explains why it matters, and notes how it interacts with the other rules. The rules exist because these specific failure modes actually happened — see `CHANGELOG/` for the commit-referenced incidents that motivated each one.

A violation of any R1–R5 rule (or any of R6–R10, or the "Prioritize Clean Architecture Above All Else" section in CLAUDE.md) FORBIDS commit. There is no "downgrade tier and ship anyway" path. The agent fixes the violation in the same working tree and re-runs all verification, OR escalates to the operator and STOPS. No commit ships at any tier with a known violation. See CLAUDE.md "AI Attribution" section.

## R1. RCA on every failure — no transient-flake classification

**The rule.** Every failure, error, anomaly, or warning surfaced by ANY tool (build, test, validator, runtime, check, deploy, lint, hook) triggers IMMEDIATE invocation of `/charly-internals:root-cause-analyzer` BEFORE any remediation attempt. The first occurrence is the investigation trigger; there is no second-occurrence threshold.

**A warning is a failure for R1 purposes.** It triggers the analyzer like any failure; the zero-warnings landing gate — a surviving warning is an R10 failure, never an accepted end state — is operationalized in `/charly-internals:git-workflow` ("Zero warnings").

**Documentation divergence is a failure for R1 purposes.** Any divergence between a doc, skill, or code comment and observed reality — discovered by ANY means (a bed run, a code reading, an agent, a human report), not only via an RDD bed-contradiction or an R5 deleted-identifier — triggers the analyzer like any failure; "it's just a doc, I'll note it" / "the code is what matters" are confessions, not defences. Its remediation is a TRANSITIVE sweep: fix not just the file where it surfaced but EVERY other doc/skill/comment carrying the same false/outdated/misleading claim (claim-keyed — the generalization of R5's identifier-keyed grep self-test). The fix for the changed surface and its sibling-set is BLOCKING — it lands in the current cutover (a tree carrying a false claim is not "correct" by R2's own test); a genuinely-unrelated divergence is RCA'd immediately too, joining its thematic batch cutover (R2 — the Cutover Sizing Law). The two narrower cases — RDD's "when the bed contradicts the doc, the DOC IS STALE" and R5's deleted-identifier sweep — are special cases of this rule. When the remediation is itself documentation-only (`*.md`, comment-only edits, or a submodule pointer bump to an all-documentation submodule commit), it is gated by the non-runtime standards rather than a bed and ships at the `documentation reviewed` tier — the Documentation-only change class (CLAUDE.md R10 + "AI Attribution").

**Forbidden first responses.** "probably a flake" / "rerun and see" / "transient" / "intermittent" / "works on retry" / "environmental" / "let me try once more" / "maybe the network was slow" / "let me clear the cache and re-run". These are confessions, not defences. Each is a way of avoiding the analysis the rule mandates.

**What is permitted.** The `/charly-internals:root-cause-analyzer` agent's 8-step process. After running it, if the analyzer concludes the root cause is genuinely external (network partition, upstream registry outage, kernel bug with a tracked upstream report), the conclusion is documented in the conversation **with evidence** — never assumed. Only after that documented conclusion is "retry" an authorized response.

**Why it matters.** Failures that look transient often aren't. A test that fails 1-in-N times because of a race condition will fail 1-in-(N/scale) times under load — pretending the failure is "flaky" hides the race instead of fixing it. R1 forces the investigation early, when the symptoms are simple, before the bug accumulates obscuring complications.

**Interaction with other rules.** R1 is the first response to ANY failure surfaced by any other rule's verification step. R7 (mandatory end-to-end gate) produces failures that R1 must investigate. R8 (generated-artifact invariants) produces failures that R1 must investigate. R10 (disposable + fresh-rebuild) produces failures that R1 must investigate. R1 is also the first response to a self-detected anomaly mid-session — including during planning, exploration, or normal coding.

## RDD. Risk Driven Development — prove the highest-risk unknowns EARLY (the proactive twin of R1)

**The rule.** ALWAYS validate ANY HIGH-RISK assumption empirically on a live `disposable: true` bed (`/charly-internals:disposable`) in the planning / early-coding phase, BEFORE the edits that depend on it. R1 runs RCA on every failure AFTER it happens; RDD runs the validation FORWARD so wrong assumptions, unnecessary cautions, and erroneous root-cause theories never survive into the final plan or code. **Never accept the skills, CLAUDE.md, or the current code as automatically correct** — docs drift and code has bugs; for a high-risk call, reality is the only ground truth. RDD is the COMPLEMENT of skills-first (R0), not a substitute for a lookup: you still load the skill first, you just don't treat its high-risk claims as proven until a bed confirms them. *Never trust, verify.*

**Risk — not documentation status — is the trigger.** Low-risk orientation ("roughly what does this layer do") is a zero-risk skill lookup (R0) — do NOT burn a bed on it. High-risk (being wrong invalidates the plan, is costly / hard-to-reverse, or would mislead RCA) is proven on a bed REGARDLESS of what any doc or code asserts. The archetypal high-risk unknown: whether a SPECIFIC layer composition, at the LATEST available versions the resolver picks, builds / deploys / runs TOGETHER — no skill can certify a never-composed combination.

| Assumption | Risk if wrong | How RDD settles it |
|---|---|---|
| "Roughly what does candy X do?" (orientation) | Low, recoverable | Skill lookup (R0) — no bed |
| "Candy X behaves EXACTLY as documented, and my plan depends on it" | High | Validate on a live bed — the skill may be stale |
| "The code does X, so my change is safe" | High | Run it — code has bugs; the emitted artifact / live run is the arbiter (R8/R9) |
| "These candies, at their latest versions, compose & run together" | High (no skill can certify) | Build + deploy + `charly check` EARLY |

**RDD prevents three failure modes:** (1) a wrong high-risk assumption baked into the design — every task built on it inherits the defect when reality differs from the stale doc or buggy code; (2) unnecessary caution / over-engineering — guards, fallbacks, or pinned-back versions added against a danger a real check would have disproven; (3) erroneous root-cause analysis — diagnosing from speculation or a stale doc / code reading instead of a real bed run.

**Forbidden internal-voice triggers.** "the layers probably compose, I'll find out at R10" / "the newest version is surely drop-in" / "each layer works alone, so the stack is fine" / "the skill says so, it's true" / "the code does X, so it's safe" / "I'll add a guard to be safe" (without proving the danger is real) / "let me bed-test what the skill already says" (for a LOW-risk item). Each either defers proving the riskiest unknown to the most expensive moment, or wastes a bed on a settled one.

**What is permitted / required.** Building the real composition, running the bed, inspecting the running deployment, reading the emitted artifact, or a focused `charly check box` / `charly check live` probe — riskiest-assumption first — to PROVE a high-risk claim before editing on it. When the bed contradicts a skill or CLAUDE.md, the DOC IS STALE — fix it in the same change (skills are living documents).

**The spike — RDD's named instrument.** A spike is a TIME-BOXED, THROWAWAY investigation (the industry term: [Spike (software development)](https://en.wikipedia.org/wiki/Spike_(software_development))) scoped to ONE named high-risk unknown, run empirically — on a live `disposable: true` bed, or against the real generator / emitted artifact when the unknown lives there (the same permitted instruments listed above). Its single purpose is to discover **HOW** to build what the plan requires; its deliverable is the **discovered mechanism — the HOW** — plus any doc/skill/memory fix the result forces (R1); NEVER shipped code. Spike code, config, and beds are discarded once the question is answered; only the knowledge lands in the plan. **A spike is a support tool for the implementation, NEVER an excuse to not do something.** It decides neither *whether the work is done* (R10 does) nor *whether the work happens at all* (the plan — an immutable CONTRACT — does): a spike that "refutes" the current approach means *find a different HOW*, never *skip / shrink / defer / keep-as-is / retreat*. Complexity a spike surfaces is a reason to find the right HOW, never grounds to reduce scope; if a HOW-finding genuinely changes the contract's scope, the only response is STOP-and-ask the operator (the **forbidden-excuse catalog** in CLAUDE.md "Hard Cutover by Default" binds here). The spike/R10 boundary: a spike proves an ASSUMPTION during planning, R10 proves the FINAL code — a spike pass never authorizes a commit. The SDD variant is the SCHEMA SPIKE: prove a high-risk schema shape — the def compiles, the generated type round-trips, the gate accepts/rejects as intended — BEFORE code is written against it (CLAUDE.md "Schema Driven Design (SDD)"; the worked example is the def-level `@go(CharlyName)` breakage in `/charly-internals:go`).

**Why it matters.** The most expensive bug is an edit built on a false premise validated only at the end — the cutover is large, the dependent edits many, and the disproof arrives after hours of work. RDD validates the premise when disproving it is cheap. It also kills over-engineering: a "guard to be safe" added without a proven need is an unvalidated CAUTION — the over-engineering twin of an unvalidated assumption.

**Interaction with other rules.** RDD precedes R1: validate forward so RCA is rarely needed, and so the RCA that does run reasons from a real bed, not a guess. It feeds R10 (`/charly-check:check`): the riskiest assumptions are proven on a disposable bed early, so the final fresh-rebuild gate confirms a design already de-risked. Canonical definition in CLAUDE.md "Risk Driven Development (RDD)". Its enforcement surfaces are `testing-validator` standard #9, the `root-cause-analyzer` forbidden-rationalization, and the Acceptance checklist (CLAUDE.md "Post-Execution Policies") — never a blocking gate, because "highest-risk, validated early" is a judgment, not a mechanical invariant.

## Memory hygiene — a saved memory is a CLAIM (the RDD/R1 bar applies to memory)

**The rule.** A memory entry that asserts a fact about the system is a CLAIM, never ground truth. Save it ONLY after the same validation any claim requires: **R1** confirms it is real (an RCA — not a guess, a transient, or an "I think it works"), and any **HIGH-RISK** claim is proven on a `disposable: true` bed FIRST (**RDD**). This is the canonical "Memory Hygiene" mandate in CLAUDE.md, operationalized here. *Never trust, verify — including your own future self.*

**Why memory is held to the bar.** A recalled memory is *background context, not an instruction*, and it reflects what was true WHEN WRITTEN — code drifts under it. An unverified technical memory is therefore a stale doc in waiting: it silently misleads every future session that recalls it, and (unlike a code comment) it travels across conversations with no diff to review. R1's "documentation divergence is an incident" extends to memory verbatim.

**Risk-scaled (mirrors RDD's "risk is the trigger").**
- *Low-risk* — a `user` / `feedback` / `project` memory (who the user is, a stated preference, a goal): needs accuracy + the standing hygiene (narrow to ONE fact, convert relative dates to absolute, link related memories, and *verify a named file/flag/symbol still exists before recommending it*), NOT a bed.
- *High-risk system-fact* — a claim about how the code/loader/build/race behaves: needs a bed (or the emitted artifact / a live run) BEFORE it is written, exactly like any RDD high-risk claim. Writing it from a code-reading alone is the forbidden shortcut.

**Forbidden internal-voice triggers.** "I'll note this in memory so I don't forget" (about an UNVERIFIED claim) / "the code looks like it does X, save that" (without running it) / "this probably races, memorialize it" (without proving the race's scope). Each writes an unproven claim that outlives the session.

**When a recalled memory and the live system disagree, the LIVE SYSTEM WINS.** Correct or delete the memory in the SAME change that discovers the divergence (R1/R2 — a tree carrying a false claim is not "correct"). Deleting a wrong memory is as load-bearing as fixing a stale skill.

**Worked example — the over-broad `.build/` memory.** A memory asserted "concurrent `charly check run` from one repo dir race on `.build/`". A code reading (`/charly-internals:generate-source`: `.build/<box>` is per-image; `/charly-internals:agents`: no global build lock) narrows that to "race only for two builds of the *same box* in the *same working dir*" — distinct-image / distinct-project-dir builds are isolated. The original memory claimed MORE than any bed ever proved, so it over-warned and shaped a plan defensively. The fix: prove the narrowed claim on a bed (the concurrency experiment), THEN rewrite the memory to exactly what the bed showed — not before.

## ADE. Agent Driven Evaluation — the spec is the test; agents author and grade it

**The rule.** Capture an entity's intended behaviour as an executable `plan:` on the CANDY that provides it (a `description:` string + a flat ordered `plan:` of steps), authored by you OR an agent (hand-edit the `plan:` or `charly candy set`). Each step declares its verifier BY KEYWORD: a `check:` step (inline verb) → a DETERMINISTIC check the runner executes; an `agent-check:` step (prose) → an AGENT grades it (`charly check feature run <deployment>` spawns the configured `kind: agent` CLI, which probes the live deployment and returns a pass/fail verdict with evidence). The plan bakes into `ai.opencharly.description` and is runnable as acceptance tests (`charly box feature run <image>` / `charly check feature run <deployment>`), drivable to green by hand OR by the `charly check run` AI loop (an `iterate:` bed). The spec IS the test.

**Risk — and the keyword choice — are author decisions, not afterthoughts.** A behaviour that can be checked mechanically (a file exists, a port answers, an MCP tool is listed) MUST be a `check:` step — deterministic, reproducible, free. Reserve the `agent-check:` step for genuinely free-form behaviour a verb can't express ("the chart looks populated", "the page recovered gracefully"). Authoring an `agent-check:` step where a deterministic `check:` would do is the over-engineering twin of an unvalidated assumption — it trades a free, reliable check for a slow, costly, non-deterministic agent call.

**Forbidden internal-voice triggers.** "the check passed, no need to look at the evidence" / "the grader is non-deterministic so I'll just rerun until it's green" (that's R1/R4 — investigate, don't reroll) / "I'll mark every step `agent-check:` and let the agent figure it out" (over-uses the grader; use a `check:` verb) / "an unparseable grader output is probably a pass" (NEVER — unparseable / timed-out / launch-failed is a FAIL) / "I'll bake a failing step as a TODO" (a baked step must PASS — a known-failing one poisons every `charly check run`).

**What is permitted / required.** Using `check:` steps for the measurable; the `agent-check:` grader for the genuinely free-form, with its evidence inspected; `charly feature pending` to find the agent-graded steps; `--no-agent` for a deterministic-only CI run (`agent-check:` steps report `unbound`, visibly, never silently green). A plan authored on a candy covers every box that composes it — author ONCE on the behaviour's provider, never per-box (R3).

**Why it matters.** "Done" without an executable definition of correct behaviour is the ambiguity ADE removes; a prose step that documents intent but verifies nothing is prose that never runs — binding it to a `check:` verb or the agent grader (an `agent-check:` step) makes it executable. And a plan on the CANDY, not the box, keeps one behaviour's acceptance in one place.

**Interaction with other rules.** ADE is the acceptance/intent layer of the same *never trust, verify* family: RDD proves the risky ASSUMPTIONS before the edit, ADE specifies WHAT correct behaviour is, R10 proves it on a fresh rebuild. It is a co-equal pillar and a MANDATORY gate for candies: every candy MUST author a non-empty `description:` string AND a `plan:` with ≥1 `check:` step — `charly box validate` hard-errors otherwise — and the baked plan runs and must pass. (Authoring is required; running the live AGENT GRADER via `charly check feature run` stays opt-in.) The grader runs inside the secured, disposable box (candyboxing). Canonical definition in CLAUDE.md "Agent Driven Evaluation (ADE)"; the how-to + the worked example live in `/charly-check:check`.

## R2. No "pre-existing" / "out of scope" / "unrelated" / "follow-up PR" classifications

**The rule.** Every issue surfaced during the active cutover — failing test, validator warning, runtime crash, deprecated-marker hit, dead-code reference, stale doc paragraph — is fixed in the SAME working tree as the cutover, OR escalated to the operator for explicit re-scoping. The classifications "pre-existing", "unrelated to this change", "out of scope", "follow-up PR", "tracked separately", "we'll get to it later" are FORBIDDEN.

**Forbidden phrasings.** "this was already failing before my change" / "unrelated to this PR" / "out of scope for this cutover" / "I'll file a follow-up issue" / "this is tracked separately" / "we can address that later" / "noted but not required for this commit" / "intentionally deferred to keep the diff focused".

**Forbidden-excuse catalog — the difficulty-, SIZE-, and PRIORITY-based sibling set.** Distinct from the deferral phrasings above, these use difficulty, size, or self-assigned "priority" to justify NOT doing (or scope-cutting) the work — equally forbidden (CLAUDE.md "Hard Cutover by Default"): the difficulty framings ("it's complicated / too difficult / too hard / too risky / touches too much / would recreate/duplicate X / the spike showed it's hard / keep the current approach"), the size framings ("it's huge / a multi-cutover sub-program / a multi-session effort / can't be finished this session / scoped as a focused effort for later / ready to grind whenever you want"), the CONTEXT framings ("I've run out of / exhausted context / continuing would leave a broken, unbuildable tree / it needs a fresh session (or fresh context) / the correct next step is a fresh session" — "would leave a broken tree" is a FABRICATED excuse with zero evidence and is never raised; running low on context is answered by compacting-and-continuing or DELEGATING the unit to a fresh teammate / sub-agent, whose whole purpose is to carry it forward with a fresh context budget, never by stopping — CLAUDE.md "Agents, Workflows & Teams"), AND the priority framings ("it's secondary / lower-priority / a nice-to-have / optional / not required / a design refinement / NON-\<gate\>, so not required"). NONE ever justifies skipping, shrinking, deferring, keeping-as-is, re-scoping, or REVERTING ALREADY-WORKING CODE; they are inputs to finding the HOW (RDD/a spike — a support tool, never an excuse), and a genuine scope-change is STOP-and-ask, never a unilateral cut. **A large cutover decomposes into atomic per-unit cutovers landed NOW, one after another** — decomposition is forward motion (land unit 1, continue), never a deferral device; reverting working code because the rest is large is the worst form of the excuse (a spike that PROVED the mechanism means keep-and-land, never revert-and-defer), and the excuse stays forbidden when dressed as "an honest assessment" / "a scoping finding" / "the spike's deliverable" / "exhaustively confirmed scope". The same rule governs architecture placement: the kernel/plugin boundary law places by kind-agnostic mechanism, never by difficulty (`/charly-internals:plugin` "The kernel/plugin boundary law").

**What is permitted — classify BLOCKING vs NON-BLOCKING first.** A **blocking** issue (the current change is incorrect, incomplete, or unsafe without it) is, by DEFAULT, **fixed in the same working tree** — you do not ask permission to fix what it found:

1. **Fix in the same working tree** (the default). Same commit as the active cutover; same atomic change; proved under the CURRENT cutover's R10.
2. **Escalate to the operator — only when the blocking issue is itself a genuine crossroad** you cannot resolve from the request, code, skills, or sensible defaults. A genuine crossroad is one of: a design choice with material trade-offs; a hard-to-reverse or outward-facing action without standing authorization; a contradiction between the plan and CLAUDE.md / a loaded skill; genuinely ambiguous requirements. The ask is explicit: "I encountered $X during this cutover. Per R2 I cannot defer it, and it is a decision I cannot make alone. Should I (a) fix it now in this same commit, (b) abort the active cutover and address $X first, or (c) explicitly re-scope?" The operator's response authorizes the path; silence does not. Escalation is the narrow crossroad exception, never the default — a blocking issue with a clear fix is just fixed.

A **non-blocking** issue (the current change is correct AND complete without it, and it is genuinely separable from this change) takes a third path:

3. **The NEXT THEMATIC BATCH CUTOVER — the batch IS the non-blocking issue's "immediate-next cutover"** (the Cutover Sizing Law: CLAUDE.md "Hard Cutover by Default" + `/charly-internals:cutover-policy` "Cutover sizing — the batch law"). Fixed right away — but landed as part of ONE large, theme-coherent batch with its OWN full R10; the batch is planned, owned, and begun the moment its first member surfaces, and a small non-blocking fix NEVER pays a solo landing ceremony (solo is reserved for blocking/urgent fixes and substantial coherent scopes). This is NOT the forbidden "follow-up / tracked separately / someday" deferral: a batch has an owner, a scope, and a start — an UNSCHEDULED fix (no batch, no owner) remains the forbidden deferral; there is no window of unverified brokenness on `main`, and no indefinite parking. The discriminator: *would shipping the current cutover WITHOUT this fix leave the tree correct and the cutover's claim true?* Yes → non-blocking (joins its thematic batch); No → blocking (paths 1–2); unsure → blocking. **Objective test for "separable":** the current cutover's OWN R10 (check-coverage + fresh-rebuild) passes and proves its claim WITHOUT the fix — the fix is neither exercised by nor changes the verdict of this cutover's test coverage; a fix that would alter this cutover's R10 result or check-coverage gate is BLOCKING. Mislabeling a blocking issue "non-blocking" to ship faster — or carving the current change's OWN scope into two cutovers — is the forbidden split; a genuinely separate concern getting its own cutover is not.

**Worked example — documentation divergence.** A doc/skill/comment found to diverge from reality runs through the SAME discriminator — no new rule (it is R1's "Documentation divergence is a failure for R1 purposes" applied here). A divergence on the surface this cutover changes — plus every sibling doc/skill/comment carrying the same claim — fails the test (shipping with a known-false doc on the changed surface leaves the tree NOT correct), so it is BLOCKING: fixed in this cutover's commit. A divergence you stumble on that is genuinely unrelated to this cutover's subject passes the test (this cutover's claim stays true and its R10 unaffected), so it joins the next thematic batch cutover (typically the docs/lessons batch) — RCA'd immediately, batch-scheduled immediately, never parked as "someday".

**Why the escape hatch is closed.** Deferring a surfaced test failure as "pre-existing, unrelated" leaves brokenness on `main` for the window between the deferral and the eventual fix — when fixing in place would have cost a few lines and 30 seconds of attention. R2 closes this escape hatch absolutely. (See `CHANGELOG/` for the incident that motivated this.)

**Why it matters.** "Pre-existing" is the most common agent escape hatch — it lets the agent claim the work is complete while leaving brokenness in the tree. Every "pre-existing" deferral compounds: the next cutover finds two pre-existing issues, the third finds three, and the codebase entropy grows monotonically. R2 forces the agent to either pay the small fix-cost now OR escalate to the operator; it removes the silent third option of "leave it".

**Interaction with other rules.** R2 covers both approved-plan phasing AND incidentally-surfaced issues mid-session: **no deferral, neither planned nor incidental.**

## R3. No code duplication; generic, reusable solutions over ad-hoc patches

**The rule.** On the FIRST surface where the same pattern, predicate, filter, transform, or guard appears in two places, refactor to ONE shared abstraction in the SAME working tree. Every fix MUST apply cleanly to ALL surfaces it logically covers, not just the surface that prompted the report.

**Forbidden patterns.** Sibling-layer naming (`<name>-host`, `<name>-pod`, `<name>-bootc` when they share content); parallel filter functions in adjacent files; per-call-site re-implementations of the same predicate; copy-pasted YAML stanzas across multiple charly.yml files; copy-pasted Go function bodies with one-token differences; "let me just patch this one consumer for now and unify later"; "the abstraction is unclear, so I'll duplicate for now and refactor when the pattern firms up".

**What is permitted.** ONE shared abstraction, in the obvious shared location. If the abstraction is unclear, the answer is to think harder, ask the operator, or escalate — not duplicate. If the cost of the refactor is high enough to warrant a discussion, escalate; do not silently duplicate.

**Why it bites.** Sibling-candy duplication (a `<name>-host` spawned for every host-vs-container difference instead of extending the one candy with init-system-aware logic) crystallizes into divergent surfaces that drift in their package lists, check probes, and service definitions — and the eventual unification deletes far more than the original duplicate. The canonical fix is ONE compile-time filter, not a per-call-site band-aid: when the same predicate appears on N targets, it collapses to one shared filter, applied to all N in the same commit. (See `CHANGELOG/` for the worked examples that motivated this.)

**Why it matters.** Duplication has compounding cost. Two divergent copies become three, then four, then eight; each copy hides bugs the others fixed. The cost of the unification grows superlinearly with the number of copies. R3 enforces unification at copy-count = 2 — the cheapest possible moment.

**Interaction with other rules.** R3 is paired with the architectural-philosophy framing in CLAUDE.md "Prioritize Clean Architecture Above All Else" — no duplication on first surface, generic over ad-hoc, no workarounds, stated there as one binding mandate that mirrors R3 + R4 from the architectural angle. Both framings are binding.

## R4. No ad-hoc workarounds — sleep loops, retry-on-flake, magic-number tuning, "works on my machine" fixes are FORBIDDEN

**The rule.** Sleep loops, retry-on-flake harnesses, magic-number tuning, hardcoded paths chosen because "the standard one was busy", environment-specific shims, and "works on my machine" fixes are FORBIDDEN. Every fix must apply cleanly across every supported environment.

**Forbidden patterns.** `sleep 5; retry` (race-condition cover-up); `for i in 1..3 do try; done` (retry loops disguising flake); hardcoded ports chosen because "8080 was busy" (port-allocation bug disguised as a config); environment-specific paths like `/Users/$USER/...` in shipped code; default-fallbacks that hide a missing config (silent fallback to a wrong value); "this is what worked when I tried it locally" (single-environment validation).

**What is permitted instead.**

| Forbidden pattern | Authorized replacement |
|---|---|
| `sleep N; check` | Synchronization primitive: file lock, readiness probe, condition variable, deterministic ordering |
| Retry on flake | Identify the race; fix the race; remove the retry |
| Magic number | Named constant, sourced from config, validated on load |
| Hardcoded port | Port allocation from a registry, or service-discovery lookup |
| Environment-specific path | Standard XDG/FHS path resolved at startup |
| "Works on my machine" fix | Cross-environment validation before the fix ships |

**The `charly` CLI is the ONLY operational interface (CLAUDE.md Key Rules).** Ad-hoc container/VM commands against charly-managed resources are R4 workarounds; every one has a `charly` verb:

| Ad-hoc command (FORBIDDEN on charly-managed resources) | The `charly` verb |
|---|---|
| `podman ps` / `docker ps` | `charly status` (`--all`, `--json`) |
| `podman inspect` (ports / mounts / state / image ref) | `charly status <box>` / `charly status --json` (structured ports, volumes, tools, `image_ref`) |
| `podman exec <ctr> <cmd>` | `charly cmd <box> "<cmd>"` (running) / `charly shell <box> -c "<cmd>"` (image) |
| `podman logs` / `journalctl --user -u charly-*` | `charly logs <box>` |
| `podman rm` / hand-editing quadlets | `charly remove <box>` (`--purge` for volumes) |
| `podman inspect` OCI labels | `charly box labels <ref>` (`--format <key>` for one value; non-zero exit when absent) |
| `podman exec`/`logs` into a SIDECAR container | `charly cmd <box> --sidecar <name> "<cmd>"` / `charly logs <box> --sidecar <name>` |
| `podman volume ls/inspect` | `charly volume list <box>` (names + mountpoints) |
| `podman volume rm <one-volume>` | `charly volume reset <box> <name>` (in-use refused; next start recreates) |
| `podman cp` | `charly cp <box> <src> <dst>` (`:` prefix marks the container side; `--sidecar` supported) |
| `podman image ls` | `charly box list tags [<box>]` (newest first; rollback via `charly update --tag`) |
| `podman rmi '<glob>'` | `charly clean --invalidate '<glob>'` (charly-labeled tags only; in-use skipped) |
| `podman secret ls` | `charly status <box>` (the `Secrets:` detail line / JSON `secrets`) |
| `podman secret rm` + re-setup | `charly config <box> --refresh-secret <name\|all>` |
| `systemctl --user status/restart charly-<x>` | `charly status <x>` / `charly restart <x>` |
| ad-hoc `supervisorctl …` | `charly service status <box>` / `charly service start/stop/restart <box> <svc>` |
| `virsh list/dumpxml/domstate/…` | `charly vm *` (lifecycle) / `charly check libvirt list/info/domain-xml/…` (introspection) |
| stray-resource cleanup by hand | `charly reap-orphans` / `charly preempt restore` |

A probe NO `charly` verb expresses is a charly GAP — close it as its own cutover (R2), never with an ad-hoc command. The mandate governs what you RUN against charly-managed resources: DESCRIPTIVE mentions of the underlying machinery (how a collector or executor works internally) are not commands and stay, and host-level operations on non-charly-managed resources (the host package manager, enabling the host libvirt daemon) are out of scope.

**The rule is preventive.** R4 exists to forbid the patterns BEFORE they crystallize. Each forbidden pattern is the kind of "quick fix" that, once accepted, becomes tribal knowledge ("oh, that test always needs a sleep; that's just how it is"). R4 closes the door before the tribe forms.

**Why it matters.** "Temporary" fixes never get removed. Every sleep loop in the codebase was added with a "this is just for now" justification that was never revisited. R4 forbids the pattern at addition time, before the temporary becomes permanent.

**Interaction with other rules.** R4 is paired with R3 in CLAUDE.md "Prioritize Clean Architecture Above All Else" (the no-workarounds norm). R4 violations also typically violate R1 — the workaround is an attempt to dodge the failure rather than RCA it.

## R5. Hard cutover: deprecated path AND every stale reference deleted in the same change

**The rule.** When a cutover introduces a replacement, the SAME commit deletes (a) the deprecated code path, (b) every comment / TODO / DEPRECATED marker referencing the old path, AND (c) every reference, comment, docstring, error message, skill paragraph, migration help-text, test fixture, or hook string naming a deleted identifier. After commit, `git grep '<deleted-id>'` returns ONLY historical mentions in `CHANGELOG/` or migration help-text.

**The acceptance test.** A cutover is not "clean" until you can run `git grep '<deleted-id>'` and have ZERO live (non-historical) hits. Historical hits in `CHANGELOG/` and migration command help-text that names the legacy form for the user's benefit are permitted — these intentionally preserve the old name to help users migrate. Everything else is a violation. The deprecated / transitional / dual-mode path is deleted BEFORE the R10 acceptance run that gates the commit, never after a green R10 — an R10 that runs with such a path still present verified a state that will not ship, and the later deletion then rides untested into the commit (the silent-skip regression below); mid-flight smoke / RDD runs WITH transitional code present stay fine, only the final-code R10 acceptance run authorizes the commit (see `/charly-internals:cutover-policy` step 2).

**Identifier-keyed vs claim-keyed sweep.** The `git grep '<deleted-id>'` self-test is *identifier-keyed* — it catches stale references to a DELETED name. But a doc can diverge from reality with NO identifier deleted: it can describe behaviour the code never had, or drift after a change that renamed nothing. That broader case is the *claim-keyed* sweep — fix EVERY doc/skill/comment repeating the same false/outdated/misleading claim, not just the one spotted. R1 ("Documentation divergence is a failure for R1 purposes") makes such a divergence an incident; the grep self-test is one instrument of the claim sweep, not its whole.

**The regression classes R5 prevents.** Two motivate the rule. First, a *silent-skip regression*: deleting the old artifact (e.g. `charly.yml`) while the replacement path quietly drops a stage it used to wire produces an artifact that builds but misbehaves at runtime — which is why the acceptance test is "rebuild from the new config, run the resulting image, observe the service reach steady-state", not just "it compiles". Second, *stale references*: a rename that doesn't sweep every mention in the same commit leaves a code search returning matches that imply the retired thing is still live. (See `CHANGELOG/` for the incidents that motivated this.)

**What is permitted in historical contexts.** `CHANGELOG/` entries and migration-command help-text that names the legacy form for the user's benefit ("rename `qc` to `charly-cachyos`"). The grep self-test distinguishes these via context.

**Why it matters.** Stale references confuse you. A code search for `qc` that returns matches in `charly.yml` suggests the deployment is still live; a search that returns matches only in `CHANGELOG/` suggests it was retired. R5's grep self-test enforces this distinction.

**Interaction with other rules.** R5 covers stale references everywhere, not just the deleted artifact itself. R5 is the cleanup discipline that R3 enables — once you've refactored to the unified abstraction, R5 ensures every old reference points to the new one.

## How R1–R5 interact with R6–R10

R1–R5 are **authoring discipline** — what you do during the work.

R6–R9 are **artifact discipline** — what the produced artifact must be.

R10 is **live-system discipline** — what the deployed-and-running system must do.

The three layers compose. A cutover that violates R3 (duplication) but passes R7 (end-to-end gate) is still a violation — the duplication is a future bug. A cutover that passes R3 but fails R10 (fresh-rebuild verification) is still a violation — the artifact failed live. The three layers are AND-gated; **all** must pass. R5 is moreover a PRECONDITION of R10's acceptance run: every deprecated / transitional / dual-mode path is deleted BEFORE that run, so R10 exercises the transitional-free FINAL code — an acceptance run over a still-transitional tree proves nothing about what ships.

Per CLAUDE.md "AI Attribution" section: a violation at any layer FORBIDS commit. The four-tier table describes the proof level the agent has when committing IS permitted; a known violation means committing is NOT permitted, regardless of tier. The agent fixes the violation or escalates to the operator — never both downgrade and ship.

## Cross-references

- `/charly-internals:cutover-policy` — the operationalization of R5 for schema/API/rename changes specifically. Cutover-policy is one of strict-policy's children — R5 governs all hard-cutover behavior, and cutover-policy operationalizes it for the most common case.
- `/charly-internals:root-cause-analyzer` agent — the R1 mandatory-invocation target. The agent's 8-step process is the only authorized first response to a failure.
- `/charly-internals:disposable` — R10's verification target. Strict-policy R5 (cutover) cooperates with R10 (verification) to ensure the post-rename state is both clean and live.
- `/charly-internals:skills` — the meta-skill for skill maintenance. R5's stale-reference sweep includes skill paragraphs; the skills meta-skill has a "When to Update Skills" row dedicated to R5 self-test failures.
- CLAUDE.md "Ground Truth Rules" — the canonical source for R1–R10. Strict-policy operationalizes R1–R5 specifically.
- CLAUDE.md "Prioritize Clean Architecture Above All Else" — the architectural-philosophy framing of R3 + R4. Both framings (procedural rules R3+R4 AND architectural-philosophy section) are binding.
- CLAUDE.md "AI Attribution" — the no-commit-on-violation clause that gives R1–R5 their teeth. Any violation FORBIDS commit. No tier downgrade. No "ship at lower tier". Fix or escalate.

## When to Use This Skill

**MUST be invoked** when:

- A failure / error / anomaly / warning surfaces from any tool, at any time during a session. R1's RCA mandate fires immediately.
- You are about to edit on a HIGH-RISK assumption — a layer composition, a newest-wins version bump, or anything a skill / CLAUDE.md / code merely *asserts* that the plan depends on. RDD's prove-it-on-a-bed-first mandate fires (never trust a doc or code reading for a high-risk call).
- A pattern, predicate, or filter is about to land in a second place. R3's first-surface refactor mandate fires.
- A sleep, retry, magic number, or environment-specific shim is tempting. R4's forbidden-patterns list fires.
- A cutover commit is about to ship. R5's grep self-test mandate fires.
- An issue surfaces mid-session that "might be pre-existing" or "unrelated to my change". R2's no-deferral mandate fires.

The skill is also a useful read **before** starting a non-trivial cutover — both as a refresher and as a way to internalize the forbidden-internal-voice triggers in each rule's "Forbidden patterns" / "Forbidden phrasings" lists.
