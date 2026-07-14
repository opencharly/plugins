---
name: disposable
description: |
  `disposable: true` is the ONE and ONLY authorization for autonomous
  destroy + rebuild via `charly update`. MUST be invoked before any task
  involving `charly update`, live verification on rebuildable targets, or
  marking a VM / container deploy as safe-to-nuke. Explains why
  disposability is a DEPLOY property (not an image property), the
  separation between load-bearing `disposable:` and informational
  `lifecycle:`, why derivation is deliberately absent, and how the
  flag makes live verification fearless on shared hosts.
---

# disposable — explicit opt-in for autonomous destroy + rebuild

`BundleNode.Disposable` is the sole source of truth for disposability: the
field on a deployment entry (e.g. `disposable: true` on a deploy node,
including a check bed) is what the unified dispatcher reads. The project ↔ per-machine
overlay merge preserves it explicitly (project-set OR overlay-set → true,
later wins when both set it).

## Why this exists

Live-deploy verification (CLAUDE.md R1, R10, and Risk Driven Development) is
mandatory — and it's much easier to carry out aggressively when you can freely `destroy →
rebuild → retest` a target without asking the user for permission
every time. But autonomous destroy is only safe on resources whose
owner explicitly authorized it. The `disposable: true` flag is that
authorization. Nothing else is.

`disposable: true` is the **lifecycle boundary of the candybox** (CLAUDE.md
"Candyboxing"): OpenCharly secures the box as a whole and stocks it with the full
toolset, and this flag is what makes that fully-stocked box safe to tear down and
rebuild unattended. The candy inside can be generous *because* the wall — and its
authorized teardown — is explicit.

On a shared host, unrelated production services with live users may
run alongside charly-managed resources. The `disposable: true` flag must
therefore be:

- **Explicit.** Default false. No derivation from anything else. A
  you write `disposable: true` on a specific deploy or nothing
  happens.
- **Per-deploy.** Set on the running deployment, not on the image.
  The same image can be deployed as disposable on one host and
  non-disposable on another.
- **Multi-instance aware.** Each deploy entry (vm.yml kind:vm, or a
  deploy entry in charly.yml) carries its own flag — two
  instances of the same image can sit at different tiers with
  different disposability.

## Schema — four orthogonal fields, clear roles

```yaml
# DEPLOY-shaped YAML (charly.yml entry):

disposable: <bool>    # LOAD-BEARING authorization. Default false.
                      #   `true` authorizes `charly update <name>` to
                      #   destroy + rebuild + restart unattended.
lifecycle: <tier>     # INFORMATIONAL ONLY. Free-form human tag.
                      #   scratch|dev|test|qa|staging|prod|custom.
                      #   Has ZERO effect on disposability.
ephemeral: <block>    # LOAD-BEARING operational mandate. Default absent.
                      #   Presence means "MUST be destroyed as soon as
                      #   it isn't needed anymore". Implies
                      #   `disposable: true` automatically (the one
                      #   documented exception to anti-derivation —
                      #   see "The ephemeral exception" below).
preemptible: <l|blk>  # LOAD-BEARING resource-arbitration. Default absent.
                      #   HOLDER side: occupies the exclusive host-resource
                      #   token(s) in `holds:`; MAY be gracefully stopped to
                      #   free them for a claimant, then MUST be restarted
                      #   (disk + definition preserved). The INVERSE of
                      #   disposable. ORTHOGONAL to the three above — no
                      #   derivation either way. The claimant side is the
                      #   sibling `requires_exclusive: [token...]` list.
                      #   See "The resource-arbitration axis" below.
```

**Anti-derivation invariant — with one named exception**:

`lifecycle: dev` does NOT make a deploy disposable. A reader
might assume it would, so the anti-derivation invariant is enforced
by `charly/classification.go` and a unit test
`TestVmSpec_LifecycleAloneDoesNotAuthorize`. If you find yourself
tempted to add "if lifecycle in {scratch,dev,test} then
disposable=true": don't. That hidden logic is the entire failure
mode this design avoids.

### The ephemeral exception

`ephemeral: ...` DOES imply `disposable: true`. This is the **only**
field allowed to derive disposability — because it strengthens the
contract rather than weakening it. "Must be destroyed when not
needed" can only be honored if "may be destroyed" is also true.

Specifically:
- `LoadBundleConfig` auto-promotes `Disposable=true` when an entry
  carries `ephemeral: ...`.
- `BundleNode.IsDisposable()` returns `Disposable || IsEphemeral()`
  so every consumer (including `charly update`) treats ephemerals as
  authorized.
- Authoring `disposable: false` together with `ephemeral: ...` is
  contradictory; the loader rejects (or auto-promotes; bool fields
  cannot distinguish "explicit false" from "default false", so the
  load-time auto-promote is the canonical behavior).

`ephemeral:` itself is the operational counterpart to `disposable:`:
- `disposable: true` says "this resource MAY be destroyed
  autonomously by `charly update`" — a permission.
- `ephemeral: true` (or block form) says "this resource MUST be
  destroyed autonomously when no longer needed" — a requirement,
  enforced by the check-runner / Gherkin (ADE) step keywords / TTL transient
  timer registered in `charly bundle add`.

The implication arrow is one-way. Disposable resources are not
necessarily ephemeral; ephemeral resources are always disposable.

## The resource-arbitration axis — `preemptible` + `requires_exclusive`

A physical host resource can sometimes be held by only ONE deployment at a
time — the canonical case is a GPU passed through to a VM via VFIO (exactly one
VM can bind the card). `preemptible` (HOLDER side) + `requires_exclusive`
(CLAIMANT side) let the resource arbiter (`charly/preempt.go`) free such a resource
on demand and give it back afterward.

```yaml
# HOLDER — a long-running deploy that occupies an exclusive resource and may
# yield it. Authored as a token-list shorthand or a block:
preemptible: [nvidia-gpu]            # shorthand → holds, default stop/restore
preemptible:
  holds: [nvidia-gpu]                # REQUIRED, non-empty: operator-chosen token name(s)
  stop: shutdown                     # graceful shutdown (default & only) — frees a VFIO device
  restore: always                    # always (default) | on-success

# CLAIMANT — a deploy/check bed that needs sole use of the resource while it runs:
requires_exclusive: [nvidia-gpu]
```

**How it works.** Before a claimant is brought up (`charly check run <bed>`, or a
standalone `charly vm create` / `charly start`), the arbiter finds every RUNNING
preemptible holder whose `holds:` intersects the claimant's
`requires_exclusive:`, **gracefully stops** each (waiting until it actually
powers off so the resource is truly released), records a crash-safe **lease**,
and lets the claim proceed. When the claim is released — the check bed tears down,
or the persistent claimant is stopped/destroyed — the arbiter **restarts** the
holders. A transient (check) claim auto-releases via `defer`; a persistent claim
releases on the claimant's teardown command.

**Standing authorization — you preempt autonomously.** Triggering preemption
is STANDING-authorized: you may bring up a `requires_exclusive:` claimant — and
thereby gracefully stop a running `preemptible` holder — WITHOUT per-run operator
confirmation. This is safe because preemption is **reversible by design**: the
holder is gracefully stopped (disk + definition preserved) and GUARANTEED to be
restarted (crash-safe `restore: always`), the OPPOSITE of an irreversible
`disposable` destroy. The confirm-before-destroy rule (CLAUDE.md "Disposable-Only
Autonomy") governs irreversible teardown of a NON-preemptible, non-disposable
resource; it does NOT gate preemption of a declared holder.

**The token is a name, not a mechanism.** `nvidia-gpu` is an operator-chosen
label for the physical resource, deliberately decoupled from HOW each side
reaches it (a VM via a PCI hostdev, a pod via `--device`/CDI). The arbiter does
pure set-intersection on tokens, so the same token unifies pod-vs-VM contention.

**Auto-allocation (the token → hardware bridge).** A token may ALSO carry a
hardware selector in the embedded `resource:` vocabulary — `resource: {nvidia-gpu: {gpu:
{vendor: "0x10de"}}}`. When a `target: vm` claimant requires such a token,
`charly vm create` AUTO-ALLOCATES the matching device: `DetectVFIO` finds a GPU by
PCI vendor, persists its whole-IOMMU-group `<hostdev>` block into the per-host
`instance.yml`, and injects it — or **FAILS HARD** when no matching card exists
(`autoAllocateExclusiveGPUs`, gpu_allocate.go). This is orthogonal to
arbitration: the arbiter frees the token (stops a holder), auto-allocation wires
the freed device into the claimant. An operator-authored `<hostdev>` (committed
`vm.yml` or `instance.yml`) always wins — auto-allocation defers, never
double-injects. A selector-less token is a pure arbitration label (no
auto-allocation). Scope today: VM passthrough (a PCI `<hostdev>`); requires
`backend: libvirt`. See `/charly-build:build` `resource:` + `/charly-vm:vm` "GPU
passthrough".

**The mode flip (vfio ↔ nvidia) + the device_lock wedge.** For a gpu-backed
token the arbiter flips the card's host driver via `applyMode → switchMode`
(the arbiter in `candy/plugin-preempt` calls its switchMode host-seam over the
HostArbiter reverse channel; the host routes it to the driver-switch in
`candy/plugin-gpu` via the gpu shims — cutover C9): a SHARED claim flips the
WHOLE IOMMU group to nvidia + regenerates CDI; an EXCLUSIVE claim flips it to
vfio. **Before any nvidia→vfio flip the arbiter first RECLAIMS every running
charly GPU-CDI pod that no active lease covers** — a leaked/stray disposable bed
whose transient, owner-PID-tied lease died with its check-runner (invisible to
the host `/proc/*/fd` holder-scan, but enumerated via `podman ps`+inspect over
the `gpuCDI` host seam) — gracefully stopping each so its `nvidia_uvm` handle is
freed (they are NOT restored: a bed past its lease is leaked state). So a leaked
GPU bed can never make the flip wedge, and a residual `EBUSY` is then a GENUINE
EXTERNAL (non-charly) client. The flip is **group-aware** (every function: display→nvidia/vfio,
HDMI-audio→snd_hda_intel/vfio) and **safe by construction** — the nvidia→vfio
detach uses `modprobe -r` (module-refcount-guarded → `EBUSY` fast-fail if a
client holds the GPU), NEVER a sysfs `unbind` of a busy nvidia, because that
hangs the nvidia `.remove` forever holding the kernel `device_lock`
(reboot-only). If a switch ever wedges anyway (a GSP-teardown stall past the
bounded deadline), the arbiter **POISONS** the token (a boot-id-keyed marker
under the preemption dir) and REFUSES it to every later claimant — including
`reconcileStranded`, so a wedged card can never be handed out to produce a
SECOND `D`-state — until a host reboot clears it. `charly vm gpu status` flags a
poisoned/wedged card; `charly vm gpu recover` clears the marker once the card is
verified healthy. Full RCA + the safe-switch model: `/charly-vm:vm` "GPU
driver-mode switch".

**Crash-safety (the restore guarantee).** A holder is NEVER left permanently
stopped. The lease ledger (`~/.local/share/charly/preemption/leases.yml`) is written
*before* any holder is stopped, and "restore" means "start every listed holder
that isn't running" — so a crash at any point is recoverable. `charly preempt status`
lists active leases and flags STRANDED ones (claimant gone); `charly preempt restore
[claimant]` reconciles them (also run automatically at the next acquire).

**`restore:` policy.** `always` (default) restarts the holder regardless of the
claim's outcome — the holder MUST survive, so it comes back even if the check
failed. `on-success` leaves the holder stopped on a FAILED claim (for operator
inspection); recover it with `charly preempt restore`.

**Orthogonal to disposable/ephemeral — no derivation.** `preemptible` neither
implies nor is implied by any other axis. A deploy may legitimately be BOTH
preemptible (the arbiter stops it) AND disposable (R10 may rebuild it); a test
holder is often both. Stopping a holder is graceful + reversible (disk + state
preserved) — the OPPOSITE of `disposable`'s destroy authorization. Enforced by
`charly/classification.go` (`IsPreemptible()` is independent of `IsDisposable()`).

## Where the fields live

- `kind: vm` entries in `vm.yml` — the VM template. Applies to
  every instance unless overridden.
- deploy entries in `charly.yml` — the container per-deploy
  counterpart. Each instance of a container image has its own
  entry, so per-instance classifications are natural.
- Per-instance VM overrides (deferred to a follow-up): will live at
  `~/.local/share/charly/vm/<domain-name>/instance.yml`. Until then,
  VMs inherit the vm.yml template classification for every
  instance.

## Visible from outside the source tree

For VMs with either `disposable: true` or a `lifecycle:` tag, the
libvirt domain XML carries:

```xml
<metadata>
  <charly:disposable xmlns:charly="https://opencharly.ai/ns/charly/1.0">true</charly:disposable>
  <charly:lifecycle xmlns:charly="https://opencharly.ai/ns/charly/1.0">dev</charly:lifecycle>
</metadata>
```

`charly check libvirt domain-xml <vm> | grep charly:` (the vm.yml entity
name) tells you the classification without opening vm.yml.

For container deploys, the authoritative source is `charly.yml` —
`charly status <name>` reflects it at runtime.

## `charly update <name> [-i <instance>]`

Resolves `<name>` as either a kind:vm entity (vm.yml) or a deploys entry
(charly.yml). It **NEVER refuses** on disposability: an explicit
`charly update` rebuilds ANY target — for a non-disposable, non-ephemeral
target it prints a one-line transparency note
(`noteUpdateDisposability` in `charly/update_deploy_dispatch.go`) and
proceeds. Sequence: destroy → rebuild → restart, ending in the shared
`charly bundle add <node>` layer re-apply for every live substrate (so a
config change — a newly-added layer or nested pod — takes effect on the
rebuilt target). `disposable: true` stays load-bearing as the
authorization for the **UNATTENDED autonomous** destroy + rebuild (CLAUDE.md
R10) and the check-runner's unattended fresh rebuild — NOT as an
`charly update` capability check. You may `charly update` a non-disposable
target directly — that is an attended action you authorize explicitly, never
the unattended autonomy the flag grants.

```bash
# Disposable: you may run this UNATTENDED (autonomous, no confirmation):
charly update arch

# Non-disposable: the command still proceeds — with a transparency note.
# (Run it UNATTENDED only with explicit authorization; running it
#  attended/directly is always fine.)
$ charly update production-api
Note: "production-api" is not marked `disposable: true` (lifecycle: (unset));
rebuilding it anyway per your explicit `charly update`.
```

Flags (authoritative list: `charly update --help`):
- `--build` — rebuild the artifact first instead of reusing it (pod:
  rebuild the image; vm: rebuild the qcow2 disk; local: n/a). Without
  it, `charly update` redeploys the artifact already in local storage (it
  does NOT auto-pull).
- `--tag <calver>` — pin the image CalVer tag.
- `-i, --instance <name>` — target a named instance.
- `--seed` / `--no-seed` / `--force-seed` / `--data-from <image>` —
  bind-backed-volume data-sync control.

## What counts as an R10 run (and what does not)

R10 (CLAUDE.md, Ground Truth Rules) means the cutover's NEW or CHANGED code
path actually executed LIVE against a fresh rebuild of a `disposable: true`
target — real subprocess invocation, real container build, real deploy probes,
real verb evaluation — with pasteable runtime output for each changed piece
(for classes with a runtime gate — see "The gate is class-dependent" below).

- **A `--dry-run` does NOT count.** Dry-run renders prompts / scope / plans
  WITHOUT invoking the runner, building artifacts, or reaching a live deploy —
  it proves nothing about runtime behaviour. Validators, unit tests, and
  dry-runs are pre-flight checks, never the acceptance gate.
- **A rebuild alone does NOT count.** The rebuild is preflight setup. If the
  changed runner / AI loop / verb evaluation never executed against the fresh
  target, `analysed on a live system` is not available; the honest tier is
  `syntax check only` paired with an explicit "R10 not yet run" — and pairing
  that tier with a commit is itself a violation: STOP and ask.

### Task-editing fraud

R10 has ONE definition; redefining it retroactively is FORBIDDEN. `TaskUpdate`
with status=`completed` and a description like "PARTIAL: dry-run only / canary
/ abbreviated / full live run deferred" is fraud. Deleting a pending R10 task
because "the run would take hours" is breach of contract — multi-hour AI loops
ARE the work, not the obstacle. Session-budget concerns NEVER downgrade R10.
If R10 genuinely cannot complete, say so plainly, commit NOTHING (main repo OR
submodule), and escalate — never both downgrade and ship silently. (The
motivating attribution-fraud incident is recorded in `CHANGELOG/`.)

### The gate is class-dependent

Which R10 gate a change needs depends on its change class: docs/comments-only
changes have NO bed to run (the non-runtime standards are their gate);
hook/workflow script edits execute the changed script live (a workflow whose
CONTROL FLOW changed runs against one matching bed); `charly` code and
candy/box/deploy config changes need a bed. The authoritative matrix is
`/charly-check:check` "R10 gate by change class".

### Scope-shrinking flags

The `iterate:`/bed config in the `check:` block IS the test specification;
scope-shrinking `charly check run` flags require explicit operator authorization
in the SAME conversation turn. The flag catalog and the rule live in
`/charly-check:check` "Flag discipline".

## Opting a deploy in

For containers, pass `--disposable` to `charly bundle add`:

```bash
charly bundle add my-test fedora-test --disposable --lifecycle test
```

This writes both fields to the charly.yml entry (flags can also be
passed independently). Omitting `--disposable` means the entry
stays non-disposable — safe default.

For VMs, edit `vm.yml` directly on the `kind: vm` entity. The
`disposable: true` field lives alongside `ram:`, `cpu:`, etc. Any
synced host picks up the change on next `charly vm create` / `charly
rebuild`.

## Multi-instance examples

### Containers

```yaml
# charly.yml — each name-first deploy entry has an independent classification.
fedora-coder:             # main instance (prod): NO disposable field → NOT disposable
    pod:
        image: fedora-coder
        lifecycle: prod

fedora-coder-dev:         # dev instance: lifecycle tag does NOT authorize rebuild
    pod:
        image: fedora-coder
        lifecycle: dev    # ← human tag only; this is NOT disposable.

fedora-coder-qa:          # explicit opt-in
    pod:
        image: fedora-coder
        lifecycle: qa
        disposable: true

fedora-coder-scratch:     # minimal: no tag, explicit disposable
    pod:
        image: fedora-coder
        disposable: true
```

`charly update` itself runs on ANY of these — you can rebuild
`fedora-coder-dev` directly and it proceeds with the
`noteUpdateDisposability` transparency note (the `lifecycle: dev`
tag is informational, never an authorization). What the
`disposable: true` flag gates is AUTONOMOUS rebuild: you (and the
check-runner) may unattended-rebuild only `fedora-coder-qa` and
`fedora-coder-scratch`; rebuilding `fedora-coder-dev` autonomously
requires explicit authorization, because a lifecycle tag does
NOT authorize autonomous destroy.

### VMs

Today, classification applies to all instances of a kind:vm entity.
If you need per-instance overrides (e.g., `charly vm create arch -i test`
with different classification than `-i prod`), that requires the
per-instance override file at `~/.local/share/charly/vm/charly-<name>-<instance>/instance.yml`
— planned follow-up.

### Per-host device overlay (`instance.yml` `libvirt:`)

The same per-domain `~/.local/share/charly/vm/<domain>/instance.yml` also carries a
`libvirt:` block — a per-host device overlay merged onto the `VmSpec` at
`charly vm create` (`VmInstanceOverride.ApplyToVmSpec`, before `RenderDomainXML`).
Only the HOST-SPECIFIC device categories merge — `devices.hostdevs` (a PCI
`<hostdev>` whose bus/slot address is host-specific) and `devices.filesystems`
(a virtiofs share rooted at an absolute host path) — appended to whatever the
committed `vm.yml` declares. This is where a GPU passthrough address and an
operator-home share live, OUTSIDE version control, so the project's `kind: vm`
entities stay PORTABLE: no PCI address, no operator-home path committed (a
card-less host simply omits the overlay, and the GPU-gated checks report N/A).
The overlay reuses the `kind: vm` `libvirt:` schema verbatim — the block is
identical to what `vm.yml` would carry; generate a hostdev block with
`charly vm gpu list`. The file still also carries `disposable:` / `lifecycle:`
(above), and yaml.v3 unknown-key tolerance keeps the formats independent. See
`/charly-internals:vm-spec` (`VmSpec.Libvirt`) and `/charly-vm:vm` (GPU passthrough).

## Extensibility

`lifecycle:` is free-form string — `scratch`, `dev`, `test`, `qa`,
`staging`, `prod` are the canonical values but any tag works
(`demo`, `perf`, `nightly` …). Tags are informational.

If a future feature wants to link a tier to behavior (e.g.
auto-expire deploys tagged `scratch` after 7 days), add a NEW
explicit field (`disposable.ttl`, `auto_cleanup: true`, etc.) —
never make `lifecycle:` behaviorally load-bearing. The
anti-derivation invariant is what keeps this classification safe
on shared hosts.

## Cross-references

- `CLAUDE.md` — R10 "Verify on a `disposable: true` target; prove
  it on a fresh rebuild", plus the "Candyboxing", "Disposable-Only
  Autonomy", and "Risk Driven Development (RDD)" sections. `disposable: true`
  is the lifecycle boundary of the candybox — the wall that makes a
  fully-stocked, secured box safe to destroy and rebuild — and the live surface
  you prove a high-risk assumption on BEFORE editing (RDD), never trusting a doc
  or the code for a high-risk call.
- `/charly-check:check` — the 10 testing standards; disposable-only deployment
  is Standard 4, fresh-rebuild re-verification is Standard 10.
- `/charly-vm:vms-catalog` — kind:vm schema, including `disposable:` and
  `lifecycle:` fields.
- `/charly-vm:arch` — canonical worked example.
- `/charly-core:deploy` — `--disposable` / `--lifecycle` flags on
  `charly bundle add`.
- `/charly:rebuild` — the rebuild verb command reference (not yet
  authored — currently living in this skill).

## When to Use This Skill

**MUST be invoked** for any task that involves:
- `charly update <name>` (determining which targets can be rebuilt
  unattended).
- Authoring / editing `disposable:` or `lifecycle:` fields in
  vm.yml or charly.yml.
- Running live verification on a rebuildable target (CLAUDE.md R10).
- Adding a feature that checks disposability (must use
  `IsDisposable()` / `IsDisposableFields()`, never derive from
  lifecycle).

Invoke this skill BEFORE reading `charly/classification.go` or the
related YAML files.
