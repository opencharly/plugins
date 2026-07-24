---
name: skills
description: |
  Skill maintenance guidelines: when and how to update skills, CLAUDE.md, and README.md.
  Use when updating documentation, feeding back operational insights, or auditing skill coverage.
---

# Skill Maintenance Guidelines

## Overview

Skills are living documents at `plugins/<plugin>/skills/<name>/SKILL.md`. They
are the primary procedural knowledge source for every supported agent harness
and are always loaded before codebase exploration. This skill covers when and
how to update them.

## Skill Dispatchers

The repository has two complete root dispatchers: `CLAUDE.md` is the
harness-specific adapter and `AGENTS.md` is the harness-neutral rulebook for
compatible readers. Keep their trigger → skill mappings and overall policy
equivalent while confining harness-specific mechanics to the adapter and
skills. When multiple triggers apply, load all matching skills before acting.
Full index: `plugins/README.md`.

## When to Update Skills

| Trigger | Action |
|---------|--------|
| Deployment step fails or needs undocumented workaround | Update the relevant `/charly-core:*`, `/charly-build:*`, `/charly-check:*`, `/charly-automation:*`, kind plugin (`/charly-image:*`, `/charly-vm:*`, `/charly-kubernetes:*`, `/charly-local:*`, `/charly-pod:*`), per-pod plugin (`/charly-jupyter:*`, `/charly-coder:*`, …), or split-foundation plugin (`/charly-distros:*`, `/charly-languages:*`, `/charly-infrastructure:*`, `/charly-tools:*`) |
| Verification check missing from image skill | Add to the image skill's Verification section |
| Skill's recommended defaults are wrong | Fix in the skill, not the project rulebook (`AGENTS.md` / `CLAUDE.md`) |
| New feature added to charly CLI | Update `/charly-core:<cmd>` or `/charly-build:<cmd>` skill + `/charly-internals:go` source map |
| New candy or box added | Create skill via `charly box new candy` scaffold or manual SKILL.md |
| Bug fix changes behavior | Document the fix in affected skills |
| Cross-skill behavior discovered | Update Cross-References in all affected skills |
| A doc / skill / comment diverges from observed reality (discovered by ANY means — not only a bed or a deleted identifier) | Treat as an incident (R1): RCA it, then sweep EVERY sibling doc/skill/comment carrying the same false/outdated/misleading claim and fix them all in the CURRENT cutover (blocking, R2). The two rows below are special cases of this |
| A live bed contradicts a skill's claim (Risk Driven Development found it stale) | Fix the stale skill in the SAME change — RDD keeps the living docs honest; for a high-risk claim the running system is ground truth, not the doc |
| Removed identifier still referenced in skill paragraph (R5 self-test failed) | Update / delete the paragraph in the SAME commit as the removal (R5) |
| Project-rulebook heading / R-number / clause name changes (they are a public API) | Sweep every mirroring surface in the SAME commit — see "Mirroring surfaces" below (R5) |
| Rule DETAIL accretes inside the project rulebook (matrix, catalog, worked example growing in place) | Move the detail to its owning skill (see the Authoritative-copy registry); the project rulebook keeps the mandate + a `*Detail:*` pointer |

## When NOT to Update Skills

- **Ephemeral issues** — use conversation context or memory
- **User-specific config** — use Claude Code memory system
- **Bug fixes in charly code** — the fix is in git; document behavioral changes in skills only
- **Anything derivable from code** — skills document *usage*, not implementation details
- **Historical / version-history content** — dated change notes, "renamed from", "previously / formerly / was", completed cutovers, retired / relocated identifiers → the repo's `CHANGELOG/` (one file per CalVer release version, `<YYYY.DDD.HHMM>.md`), NEVER a skill or the project rulebook. Skills describe current behavior in present tense only. When a cutover lands, write its narrative to the release's `CHANGELOG/<YYYY.DDD.HHMM>.md` (the version shared by the changelog filename and the release tag) and state the new standing rule forward-looking in the skill, with no history.

## How to Update

1. Edit the skill file at `plugins/<plugin>/skills/<skill-name>/SKILL.md`
2. If the insight affects cross-skill behavior, update the project rulebook (`AGENTS.md` / `CLAUDE.md`) too
3. After any non-trivial deployment session, ask: "Did we learn anything that future sessions should know?"

## Skill File Structure

```markdown
---
name: <skill-name>
description: |
  One-sentence description of when to invoke this skill.
  For layers: "Use when working with <component>."
  For images: "MUST be invoked before building, deploying, or troubleshooting the <image> image."
---

# <Title>

## Overview / Properties
## Key Sections (varies by type)
## Cross-References (related skills)
## When to Use This Skill
```

## Rulebooks vs Skills

| Content type | Where it belongs |
|-------------|-----------------|
| Project philosophy, architecture, key rules | harness root rulebook (`CLAUDE.md` or `AGENTS.md`) |
| Command usage, flags, examples | `/charly-core:<cmd>` or `/charly-build:<cmd>` skill |
| Layer properties, packages, ports | per-pod plugin (`/charly-jupyter:<name>`, `/charly-coder:<name>`, …) or split-foundation plugin (`/charly-distros:*`, `/charly-languages:*`, `/charly-infrastructure:*`, `/charly-tools:*`) for base layers |
| Image composition, deployment, verification | per-pod plugin or `/charly-distros:<name>` / `/charly-infrastructure:<name>` for base images |
| Skill disambiguation (which skill to use) | the active harness root rulebook's R0 Skill Dispatcher |
| Detailed operational patterns | Relevant `/charly-core:*` / `/charly-build:*` / `/charly-check:*` / `/charly-automation:*` / kind-plugin skill |
| Hard rule / gate / mandate (the WHAT and the MUST) | each harness root rulebook, with equivalent policy and an owning-skill pointer |
| Operationalization / matrix / catalog / worked example (the HOW) | The ONE owning skill (see the Authoritative-copy registry below) |
| Version history / past changes / renames / cutover narration | the repo's `CHANGELOG/` (per-CalVer `<YYYY.DDD.HHMM>.md`) — never the project rulebook or a skill |
| Long-term thesis / vision / aspiration ("why & where it's going") | `VISION.md` (repo root) — never restating command usage, architecture, or history |

## Mandate in the harness rulebook, detail in the skill

The canonical split for every rule: **each harness root rulebook states the
equivalent mandate and points at exactly one owning skill; the owning skill
carries the operationalization** —
forbidden-pattern catalogs, decision matrices, worked examples, command
sequences. Every other document links to the owner and NEVER restates it
(restated copies drift; the linked original cannot).

The complete harness rulebooks own the **Skill Dispatcher**, **RDD**, **ADE**,
and **SDD** mandates, the acceptance checklist, and AI-attribution tiers. Keep
their policy equivalent while preserving harness-specific tool language.

### Authoritative-copy registry

| Matrix / catalog / definition | Sole owner |
|---|---|
| "R10 gate by change class" matrix (incl. the class → gate → tier cross-walk) + "Flag discipline" catalog | `/charly-check:check` |
| R1–R5, RDD (incl. "The spike"), ADE operationalization (forbidden patterns, risk table, worked examples) | `/charly-internals:strict-policy` |
| SDD operationalization (the schema→generated-code pipeline map, the schema-change recipe, the generation-coverage current state) | `/charly-internals:go` |
| Hard-cutover workflow, forbidden patterns, deliverables | `/charly-internals:cutover-policy` |
| `disposable:` / `preemptible:` flag semantics, "What counts as an R10 run" | `/charly-internals:disposable` |
| Landing mechanics (branch loop, the two-step PR + `pr-validator` merge/tag, CalVer-generated-at-merge, branch protection, multi-repo order) | `/charly-internals:git-workflow` |
| Agent/workflow/team primitives, hooks doctrine | `/charly-internals:agents` |
| Kernel/plugin doctrine (core = kernel; every capability a plugin candy), the two authoring shapes, placement, the three-lane transport doctrine, the seams catalog, **the kernel/plugin boundary law** (E/M/B/D/R) + the incomplete-seam mandate | `/charly-internals:plugin` |
| Skill Dispatcher, RDD/ADE/SDD mandates, acceptance checklist, attribution tiers, Documentation-only change class anchor, Key Rules index | harness root rulebooks (`CLAUDE.md` and `AGENTS.md`) |

## Mirroring surfaces — sweep when rulebook wording changes

**The project rulebook's section headings, R-numbers, and named clauses ("flag-override
clause", "gate by change class", "Documentation-only change class",
"documentation reviewed" tier, "Acceptance checklist", "Post-Execution
Policies", …) are a public API.** These surfaces reference them and MUST be
swept in the SAME commit as any rename or removal (R5):

- the 5 hooks in `.claude/hooks/` (`runtime-verification-reminder.sh`,
  `end-of-turn-challenge.sh`, `team-coordination-reminder.sh`,
  `pre-commit-gate.sh`, `pre-push-gate.sh`),
- the 6 agents in `plugins/internals/agents/*.md`,
- the 8 per-directory signpost `CLAUDE.md` files (`charly/`, `candy/`,
  `plugins/`, each `box/<distro>`),
- the workflows in `.claude/workflows/*.js`,
- every SKILL.md that quotes a section name (grep before assuming).

The sweep test: `grep -rn '<old phrase>'` across the superproject + submodules
returns only `CHANGELOG/` context afterwards. Prefer keeping headings and
clause names STABLE when rewording content — a stable name keeps every
mirroring surface valid for free.

## Command skills vs topic skills

Most skills under `plugins/charly-core/skills/` and `plugins/charly-build/skills/`
map 1:1 to a top-level charly command (e.g. `/charly-build:build` ↔ `charly box build`,
`/charly-core:charly-status` ↔ `charly status`).
**Topic skills** are the exception: they don't correspond to a
top-level command but cover a cross-cutting concept surfaced by flags
or layer composition. Today's topic skills:

| Skill | Surfaced via | What it covers |
|---|---|---|
| `/charly-automation:enc` | `charly config --encrypt`, `charly config mount`, `charly config unmount`, `charly config passwd` | Encrypted-volume (gocryptfs) semantics, keyring resolution, `charly-enc-<image>-<volume>.scope` lifecycle |
| `/charly-automation:openclaw-deploy` | Composing `openclaw-*` layers | OpenClaw AI gateway deployment story |
| `/charly-automation:sidecar` | `charly config --sidecar tailscale` | Sidecar-container model, pod networking, env-var routing |

When adding a new command, always create a matching command skill. Consider a topic skill when a concept spans multiple commands or layers and the natural home isn't any single command's skill. Keep the frontmatter `description:` explicit about the topic nature (the blocking `Skill:` tool dispatcher matches on description keywords).

## Plugin Structure

Plugins are sorted into four use-case buckets. Directory names live at
`plugins/<name>/` (no `charly-` prefix); plugin.json `name:` fields keep the
`charly-` prefix; every skill is invoked as `/charly-<plugin>:<skill>`.

The authoritative per-plugin skill counts and purposes are the bucket tables
in `plugins/README.md` — point there, never copy them (counts drift).

## Agent & signpost conventions

### Agents (`plugins/<plugin>/agents/<name>.md`)

Sub-agents are markdown + YAML frontmatter (`name`, `description`, `tools`,
`model`, …), discovered from a plugin's `agents/` directory
(`charly-internals/agents/`, `charly-automation/agents/`). **Plugin-loaded agents IGNORE the `hooks`,
`mcpServers`, and `permissionMode` frontmatter fields** — keep those out of
plugin agents (use `.claude/agents/` or `settings.json` if you genuinely
need them). The charly roster splits into **enforcers** (root-cause-analyzer,
layer-validator, testing-validator — gate claims) and **executors**
(check-bed-runner, deploy-verifier — drive `charly check` and return verbatim
proof). Full story: `/charly-internals:agents`. Dynamic workflows are NOT plugin
content — they live in the superproject's `.claude/workflows/*.js`.

### Per-directory CLAUDE.md signposts (hybrid)

The repo-root `CLAUDE.md` is the complete R0–R10 harness adapter.
Per-directory `CLAUDE.md` files (`charly/`, `candy/`, `plugins/`, and each
`box/<distro>` submodule) are THIN signposts only: they name the skills to
load for that area and point back to root. They MUST NOT restate any rule body —
duplication drifts (an earlier layer-validator and the reminder hooks both drifted
exactly this way; the reminder hooks now name rules as pointers/triggers, never
restating their bodies). Subagents and teammates load the full `CLAUDE.md`
hierarchy from their working directory, so a signpost reaches a worker scoped
to that subtree without bloating root. Compatible harnesses that read
`AGENTS.md` use its independent, harness-neutral dispatcher and do not depend
on these signposts.

## Two-Layer Sync Architecture

The project uses two complementary sync mechanisms with `.gitignore` as the
boundary:

| What | Synced by | Visibility |
|------|-----------|------------|
| Code, `AGENTS.md` / `CLAUDE.md`, skills, layers, images | Git | Public (committed) |
| `.claude/memory/` (auto-memory) | Syncthing | Private (gitignored) |
| `.claude/settings.local.json` (personal overrides) | Syncthing | Private (gitignored) |
| `.claude/settings.json` (project policy) | Git | Public (committed) |

Memory setup: `autoMemoryDirectory: ".claude/memory"` in
`.claude/settings.local.json`. Both `settings.local.json` and `memory/`
propagate via Syncthing so your working state follows you across machines
without polluting the public repo.

Rule of thumb: **if it's useful to every contributor, it lives in git**
(skills, `AGENTS.md` / `CLAUDE.md`, code). **If it's useful only to you, it lives in the
Syncthing-synced half** (memory, personal settings).

**A generalizable PROVEN insight saved only to memory is a knowledge LEAK — every
other charly user (and every fresh validator/teammate, which never reads your
memory) re-hits the same problem and re-derives the same fix.** So the moment an
insight is PROVEN (a spike verdict, a discovered mechanism, an operational
failure-mode + its fix), codify it into the OWNING committed skill IMMEDIATELY as
a documentation-only cutover — never batch codification to a program-end docs
phase, and never let memory be its only home. Memory keeps the operator-specific
remainder: host facts (this box's hardware, enabled features), personal
preferences, in-flight session state. The test: *would a stranger cloning the
repo want this?* Yes → committed skill, now. Only you → memory. (Skills also
survive context compaction — conversation context does not — which is the same
reason insights can't live only in the transcript.)

## Skill↔code source-map sync audit

Many skills carry a *source map* of the Go code — `Source:` frontmatter, file-listing
tables (`| charly/foo.go | … |`), and inline identifier references (type/function names).
These silently desync when the code is refactored (a renamed file or symbol that no
skill's grep self-test caught). Audit and fix them as follows:

1. **Extract the claims**: pull every `charly/*.go` filename reference and identifier
   reference out of the skills, and check each against the live source — file exists?
   symbol still defined? (`gopls`/`grep` confirm.)
2. **Search INSIDE the submodule**: `plugins/` is a git submodule, so a superproject
   `git grep -- plugins` is a **FALSE ZERO** (git grep does not cross the gitlink). Use
   `git -C plugins grep` or filesystem `grep -rn`.
3. **Filter the false-positive classes** before flagging:
   - URL substrings (`pkg.go.dev`, `dl.google.com` → matches `.go`),
   - substring artifacts (`mcp.go` contains `p.go`; `localpkg.go` contains `pkg.go`),
   - legitimate non-charly refs (upstream files like `storage_dest.go`),
   - prose anti-pattern examples (a skill *mentioning* `deprecated.go` as a thing to avoid).
4. **Claim-keyed sweep (R5)**: a stale claim is fixed across EVERY skill that repeats it,
   not just the file where it surfaced — `git -C plugins grep '<claim>'` returns only
   CHANGELOG context afterwards. **Key the grep to the CLAIM CLASS — every wording AND
   syntactic variant of the false claim — NOT the one surfacing string you just edited:
   the same false claim survives under a paraphrase and under a singular/plural or
   wrapper-form variant (a retired-grammar `vms:` fix must ALSO grep the `vm:`-wrapper,
   `cpus:`, and `deployments:` variants of the same dead grammar; a sweep keyed only to
   the first string leaves a sibling variant alive and costs a second validator round).**
   The sweep also covers the cutover's OWN freshly-drafted narrative — the CHANGELOG
   entry (step 5), PR description, and commit message — since a false claim can be
   reintroduced there even when every pre-existing skill was correctly fixed.
5. **Land docs-only**: skill edits are the Documentation-only change class →
   `documentation reviewed` (no beds); the plugins commit carries a
   `CHANGELOG/<YYYY.DDD.HHMM>.md` entry too (every plugins landing does — `plugins`
   is no CHANGELOG-exception); plugins commit → superproject pointer bump → both
   tagged `v<YYYY.DDD.HHMM>` at merge (`plugins` is tagged too, same as every repo —
   the one finalized CalVer names both its changelog file and its tag). See
   `/charly-internals:git-workflow`.

**Alias residue is a special case — never assert its exact location.** A `charly/*_aliases.go` line is
transitional K-wave residue that ZERO-ALIASES/K5 deletes, so a skill asserting its EXACT per-symbol
file:line desyncs on every alias relocation AND documents a path already scheduled for deletion. State the
STABLE spec-source (the owning plugin/sdk package) and the K5-dissolution destination instead of a
concrete alias location, and `grep -rn` every concrete alias-attribution claim (a file:line or symbol
name) against the live tree before asserting it. Motivating incident: a go-skill row produced 5
alias-attribution errors across 5 validation rounds by naming exact residue locations that had already
moved.

The code-side companion (golangci-lint, the `.go` compliance checklist) is
`/charly-internals:go-quality`.

## Cross-References

- `/charly-internals:go` — Source code structure, adding new commands
- `/charly-internals:generate-source` — Understanding generated Containerfiles
- `/charly-internals:agents` — Sub-agents, dynamic workflows, agent teams; how they drive the `charly check` beds; the hooks doctrine; the signpost convention
- `/charly-build:validate` — Validation rules
- All `/charly:*` skills — Individual command documentation

## When to Use This Skill

Invoke when updating documentation, creating new skills, auditing skill coverage, or deciding where new information belongs (the project rulebook vs skill vs memory).
