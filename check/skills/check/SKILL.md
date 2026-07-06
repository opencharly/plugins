---
name: check
description: |
  MUST be invoked before any work involving: `charly check` (image / live / run),
  the plan steps / `description:` field in a candy/box `charly.yml`, the disposable test-bed deploys in a project's `charly.yml`,
  the `ai.opencharly.description` OCI label (where the baked plan travels), the AI iteration harness loop,
  `kind: agent` (the agent grader) and the disposable R10 deploys
  (`disposable: true`, run via `charly check run <bed>`), or any plan step / Op
  authoring. Covers the unified `charly check` surface: three
  primary modes (image / live / run),
  ZERO in-core live-container probe verbs — every live-container check verb (cdp/wl/vnc/dbus/mcp/record/kube/adb/appium/spice/libvirt) is served out-of-process by its plugin candy,
  verb catalog (file/port/command/http/package/service/process/dns/user/
  unix_group/interface/kernel-param/mount/addr/matching), runtime variable
  resolution (`${HOST_PORT:N}`, `${VOLUME_PATH:name}`, `${CONTAINER_IP}`,
  `${ENV_*}`), charly.yml overlay rules, authoring gotchas learned the hard
  way (package renames, absent binaries, host vs container network routing),
  AI-iteration loop semantics (plateau-bounded, progressive plan-step
  disclosure, watchdog), and the `include: <kind>:<name>` step for composing a
  bed's plan from existing candy/box/pod/vm plans.
---

# Check — unified declarative + AI-iteration evaluation

## Disposable test-bed deploys + `charly check run <bed>` — config-driven R10 acceptance

The disposable R10 test beds are **`disposable: true` deploys in the project
`charly.yml`** — a check bed is just a deploy marked `disposable: true`, there is
no separate `check:` block. A deploy is a top-level entity resolved by name, so
every deploy verb resolves a bed by name; `charly check run <bed>` drives the
full R10 sequence on it:

This is the **ecosystem-wide** rule: every repo-shipped disposable test bed —
the main repo's beds AND every `box/<distro>` submodule's beds (the arch /
cachyos / debian / ubuntu / fedora bootstrap-VM and pacstrap/debootstrap beds) —
is a `disposable: true` deploy, a top-level entry in that repo's `charly.yml`. A
test bed is ALWAYS `disposable: true`; the lone non-disposable deploy a repo
ships is an operator profile, not a test bed (the cachyos submodule's
`charly-cachyos` workstation profile); operator deployments otherwise live in the
per-host `~/.config/charly/charly.yml`. `disposable: true` is the sole
authorization for the unattended destroy + rebuild on any of them.

A bed is a **candybox** (CLAUDE.md "Candyboxing"): a disposable, secured
container / VM stocked with the FULL toolset — the entire `charly check` probe surface
(cdp/wl/dbus/vnc/mcp/adb/appium/kube), nested podman, real package managers, the
whole layer/image library — so the AI can build, deploy, and prove the *real*
composition inside it (the substance of RDD), and `disposable: true` makes
tearing it down and rebuilding fearless. The box is restricted at the boundary,
never by stripping the candy.

1. `charly box build <image> --dev-local-pkg` — build the test artifact (pod beds only). The check-bed runner sets `--dev-local-pkg` AUTOMATICALLY, so a bed bakes the **in-development** charly toolchain (any `localpkg:` candy built from local source) — never a stale published release. A bed thus always tests the code under development; a production box build downloads the released package. See `/charly-tools:charly` "Check-vs-production binary source" + `/charly-internals:install-plan` "Check-vs-production charly toolchain".
2. `charly check box <image>` — box-section + baked candy-section probes.
3. `charly bundle add <bed> <ref>` — apply the bed (or `charly vm create` for vm beds).
4. (pod beds) `charly config <bed>` + `charly start <bed>`.
5. `charly check live <bed>` — full three-section live probe pass.
6. `charly update <bed>` — fresh-rebuild re-verification (R10 acceptance gate).
7. `charly remove <bed>` (or `charly vm destroy`) — leave the host clean.

**The bed tests the LATEST LOCAL candies — not the pinned remote.** Step 1 also
points a bed's parent-repo `@github.com/<org>/<parent>/candy/...:<tag>` candy refs
at the LOCAL superproject working tree — the candy-ref analogue of the auto
`--dev-local-pkg` toolchain build above. `runCheckBed` auto-appends a
`CHARLY_REPO_OVERRIDE` for the bed project's OWN superproject (detected via `git
rev-parse --show-superproject-working-tree`; the ref's `:vTAG` is ignored, so the
bed always builds the dev's current tree). So a `box/<distro>` submodule bed —
which pulls main's shared candies via `@github` refs — verifies the IN-DEVELOPMENT
candy tree; without this it would build the STALE pinned remote candy and serve no
purpose. An explicit operator `CHARLY_REPO_OVERRIDE` entry for the same repo still
wins (it is placed first). A bed whose project is its own root needs no override —
its candies already resolve from the local tree. Source:
`selfSuperprojectOverridePair` + `mergeRepoOverrides` (`charly/refs.go`), applied
in `runCheckBed` (`charly/check_bed_run.go`); the underlying `CHARLY_REPO_OVERRIDE`
is the Go-`replace`-style "verify before you push" mechanism.

**Exclusive-resource preemption wraps the sequence.** When a bed declares
`requires_exclusive: [token...]` (e.g. a GPU-passthrough bed needing the one
physical card), `runCheckBed` acquires a resource-arbitration lease BEFORE step 1
and `defer`-releases it after teardown: any running `preemptible` holder of the
token (e.g. the operator's GPU workstation VM) is gracefully stopped — and the
arbiter waits until it actually powers off so the device is freed — then restored
when the bed finishes (even on failure, for `restore: always`). A holder is never
left stopped: `charly preempt status` / `charly preempt restore` recover a crashed run.
Triggering this — running a `requires_exclusive:` bed that stops the operator's
`preemptible` GPU holder — is STANDING-authorized (no per-run confirmation): it is
reversible by design (graceful stop + guaranteed restore), not a destroy.
See `/charly-internals:disposable` "The resource-arbitration axis" + `/charly-core:deploy`.

**A GPU bed runs on a passthrough host where host `nvidia-smi` FAILS — that is the
READY state, not a blocker.** A `requires_exclusive: [nvidia-gpu]` bed needs the card
bound to the `vfio-pci` host driver so the guest VM can claim it via VFIO; host-side
`nvidia-smi` / `rocm-smi` failing is therefore EXPECTED and does NOT mean the bed
can't run — the GPU comes alive INSIDE the guest. Gauge readiness with `charly vm gpu
status` (or `charly vm gpu list` / `lspci -nnk` → `Kernel driver in use: vfio-pci`),
NEVER host `nvidia-smi`. See `/charly-vm:vm` "GPU passthrough (VFIO)".

A `requires_shared: [nvidia-gpu]` bed (a GPU CDI pod) makes the arbiter flip the
WHOLE IOMMU group vfio→nvidia at deploy and back nvidia→vfio at teardown — the
group-aware, `modprobe -r`-gated switch (`charly vm gpu mode`/`status`/`recover`).
NEVER manually sysfs-`unbind` a busy nvidia to "free" a card between bed runs:
that hangs the kernel `device_lock` (reboot-only). If a card shows wedged/poisoned
in `charly vm gpu status`, a host reboot is required; the arbiter refuses a poisoned
token until then. Full model + RCA: `/charly-vm:vm` "GPU driver-mode switch" +
`/charly-internals:disposable` "resource-arbitration axis".

`charly check run <bed>` runs exactly ONE bed. Flags: `--keep` (don't
tear down), `--no-rebuild` (skip step 6) — both scope-shrinking, governed by
"Flag discipline" below. Per-run logs land in
`.check/<bed>/<calver>/` (per-step `.log` files + `summary.yml`). To run a
WHOLE ROSTER, fan the beds out CONCURRENTLY — one `charly check run <bed>`
process per agent — via the `/verify-beds` workflow (or an agent team), which
collapses wall-clock to ≈ the slowest single bed (see "Approximate wall-clock"
below).

### Flag discipline — the `iterate:`/bed config IS the test specification

The `iterate:` block / the deploy config in the project's `charly.yml` IS the
test spec; the operator authorizes overrides, not Claude. Passing ANY
scope-shrinking flag to `charly check run` (or `charly check live`) without the user
explicitly naming that flag in the SAME conversation turn is the same fraud
class as dry-run-as-R10 (CLAUDE.md R10 flag-override clause). The catalog:
`--plateau-iteration`, `--max-scenario`, `--tag`, `--skip-rebuild`,
`--on-pod` / `--on-vm` / `--on-host`, `--keep-repo`, `--dry-run`, and the bed
flags `--no-rebuild` (skips the R10 fresh-rebuild gate) and `--keep`.
(Fanning the FULL ROSTER out concurrently via `/verify-beds` — one `charly
check run <bed>` per agent — is scope-EXPANDING, not shrinking: it is in-spec
WITHOUT authorization when "R10 gate by change class" mandates the full
fan-out for a cross-cutting change, and needs authorization only as a
SUBSTITUTE for the class-mandated gate.) Internal-voice triggers — "tractable wall-clock", "for the
canary", "to fit session bounds", "shorten this run", "skip the heavy leg",
"faster iteration cycle" — are confessions, not defences. The `iterate:`
block's `plateau_iteration` and the AI's `progress_no_improvement_timeout` together
define the AI's recovery budget per phase; narrow neither without explicit
authorization. Speed levers that do NOT shrink scope (e.g. `--podman-jobs`, `--jobs`) need
no authorization — the lever catalog is `/charly-internals:agents` "Speed
levers".

**Run retention (`defaults.keep_check_runs`).** After `charly check run` (any path —
bed / `iterate:` entity), `.check/<name>/` is trimmed to the newest N run
artifacts (CalVer run dirs, `runs/<id>/` dirs, `result-<calver>.yml`) so harness
output doesn't accumulate unbounded. `NOTES.md` (the durable Syncthing-replicated
memory) is ALWAYS preserved. Set `defaults.keep_check_runs` in `charly.yml`
(`0`/absent disables); apply on demand with `charly clean --check`. See
`/charly-core:clean`.

### The ecosystem's disposable test-bed deploys

| Bed | Target | Ref | Surface |
|---|---|---|---|
| `check-sway-browser-vnc-pod` | pod | `image: sway-browser-vnc` | cdp/wl/vnc/dbus/mcp/record + pod-side file/service/port/process/http |
| `check-k3s-vm` | vm | `from: k3s-vm` | kube (all 13 methods) + guest-side file/service/port/process, http via port-forward, the external vm deploy end-to-end |
| `check-pod` | pod | `image: check-pod` | combined mechanism bed: `candy:` image build (a `candy:` carrying `base:`/`from:`) + `candy:` layer composition order + `kind: pod` runtime (nc :18794 + supervisord) + every DeployTarget rendering path |
| `check-local` | local | `from: check-local-app` | `kind: local` layer apply via ShellExecutor |
| `check-jupyter-pod` | pod | `image: jupyter` | jupyter-mcp regression coverage |
| `check-jupyter-ml-pod` | pod | `image: jupyter-ml` | jupyter-ml spacy/quarto + GPU MCP probes |
| `check-versa-pod` | pod | `image: versa` | versa OSM analytics + vector-tile + marimo MCP |
| `check-android-emulator-pod` | pod | `image: android-emulator` | Android 14 emulator (/dev/kvm) + adb/appium |
| `check-charly-vm` | vm | `from: charly-vm` | `charly` toolchain localpkg deploy witness (opencharly-git pacman install + dep auto-resolve) on the cloud VM |

Bed HOMES: the main repo's `charly.yml` owns `check-k3s-vm`, `check-local`, and
`check-charly-vm`; the pod beds above are top-level deploys in the `box/<distro>`
submodules' `charly.yml` (`check-pod`, `check-jupyter-pod`, `check-jupyter-ml-pod`,
`check-sway-browser-vnc-pod` in `box/fedora`; `check-versa-pod`,
`check-android-emulator-pod` in `box/cachyos`) and run from that submodule
(e.g. `charly -C box/fedora check run check-pod`).

Naming: `check-<descriptor>-<kind>`, dropping a redundant suffix when the
descriptor already equals the kind AND the short form is free (`check-local`,
`check-pod`). The harness AI-sandbox pod (the `iterate:` block's `sandbox:`
target) is named
`check-sandbox`, kept disjoint from these beds. Nothing in the `charly` Go code
hardcodes that name — it flows from the `iterate.sandbox:` field through
`ResolveIterateSandbox`, and prompts reference it via the `${TARGET_NAME}`
substitution token. **The sandbox is an OPERATOR-PROVISIONED per-host
deploy** — the runner restarts-but-never-creates it: provision once with
`charly bundle add check-sandbox <ref> --disposable` + `charly start
check-sandbox` (the ref must provide charly + nested podman + the configured
AI CLI; the per-host overlay never ships with the repo). On a host without
the entry, `charly check run <bed>` fails fast with exactly that
remediation. The supporting
`vm: k3s-vm` + `k8s: vm-k3s-vm` entities live in the project `charly.yml`
alongside its beds. `disposable: true` is the sole authorization
for the unattended destroy+rebuild (see `/charly-internals:disposable`). Two
load-time guards back the beds: `validateCheckBeds` enforces the deploy's substrate
kind ∈ {pod, vm, local, android}, a resolvable cross-ref, and `disposable: true`;
`foldCheckBeds` enforces the deploy's name is disjoint from every other deploy.
Neither checks host ports —
disjoint ports across beds are the AUTHOR's responsibility (an overlap fails the
second bed at deploy via `CheckPortAvailability`).

### Approximate wall-clock (10-CPU 32-GB reference host)

`check-pod` ~110s (one build → deploy → check → fresh-update → teardown cycle
covering all four mechanisms) · `check-local` ~45s · `check-k3s-vm` ~5–7 min · the
heavy feature beds (`check-sway-browser-vnc-pod` ~14 min incl. image build)
longer. **`charly check run <bed>` runs exactly ONE bed, so a roster run is N
of them — and running them SEQUENTIALLY would make wall-clock ≈ the SUM.** To
collapse that to ≈ the slowest single bed, fan the beds out CONCURRENTLY at the
AGENT layer — one `charly check run <bed>` process per agent/teammate
(`/verify-beds` and an agent team both do this; see `/charly-internals:agents`
"Speed levers"). The dominant cost is
the step-1 `charly box build`: a pod bed builds the image ONCE — the "fresh
`charly update`" R10 step is a `systemctl restart` onto the already-built image, not
a second build — and same-base beds share cached layers, so pre-warming a shared
base once makes every sibling bed's build incremental.

**Handling a long-running bed — by mechanism, not by who owns it.** A VM/emulator
bed's `charly check run` orchestrator runs for minutes-to-tens-of-minutes AND the
libvirt domain / emulator it spawns outlives a single turn. (1) **Launch it as a
harness-tracked background task** (`run_in_background`) — never foreground (the
Bash tool's `timeout`, 120s default / 600s max, kills the call mid-`vm-create`,
orphaning the domain) and
never a sleep/poll loop (the R4 bandaid). (2) **Let the completion notification
drive the next step** — the harness re-invokes the LAUNCHING session when the run
exits, so the launcher must SURVIVE to completion to be notified: the persistent
main session does; an ephemeral sub-agent (returns synchronously) and an idle
teammate (torn down on idle) do NOT, and orphan the bed. EVERY full `charly check run <bed>`
is a `run_in_background` task owned by a PERSISTENT owner that survives across
turns to be notified — the main session, a background agent, or (interactive
tmux) a split-pane teammate; an in-process teammate CANNOT. Duration-independent;
the 600s is a Bash FOREGROUND cap, irrelevant to a backgrounded bed.
Teammates/sub-agents do bed-local edits + short foreground checks (`charly check
image`), never the full run. (3) **Reconnect via durable state** —
`.check/<bed>/<calver>/summary.yml` + the live domain ARE the truth: "done" =
summary.yml present; "alive" = the orchestrator is in the process table; clean up
an orphan (`running` domain, no live orchestrator) with `charly vm destroy <entity>`
(or `charly remove <name>` for a pod) before re-running. See `/charly-internals:agents` "The binding rule".

### Prereq for the vm bed

`check-k3s-vm` depends on the **libvirt user-session daemon**. Enable once:

```bash
systemctl --user enable --now virtqemud.service     # libvirt >= 8 (modular)
# OR (older monolithic):
systemctl --user enable --now libvirtd.service
```

(The host libvirt daemon is host infrastructure, not a charly-managed
resource — enabling it via systemctl sits outside the charly-CLI-only
mandate's scope.)

`charly check run check-k3s-vm` best-effort starts the unit before `charly vm create`
(via `startLibvirtUserSession()` in `charly/vm.go`), and `resolveVmBackend()` now
spawns it too **before** probing the socket — so a cold socket is never mistaken
for "libvirt absent" (Arch/CachyOS ship no persistent `virtqemud.socket`; the
socket appears only after an autospawn). **Never gauge libvirt readiness with
`systemctl is-active virtqemud.service`** — a socket-activated / autospawn daemon
reports the service `inactive` while libvirt works fine; check the socket
(`$XDG_RUNTIME_DIR/libvirt/virtqemud-sock`) or `virsh -c qemu:///session list`
instead. `resolveVmBackend()` surfaces
a clear error when libvirt is absent. The `k3s-vm:` vm template pins
`backend: libvirt` explicitly so the silent `auto -> qemu` fallback can't mask
a missing daemon. See `/charly-vm:vm` "Prereq", `/charly-check:libvirt`.

### Why this is config-driven

Beds are `disposable: true` deploys; the runner reads the deploy node directly.
This means the runner works for ANY deploy an operator defines — `charly check
run <name>` resolves the deploy by name through the same path every deploy verb
uses, with no hardcoded bed table to keep in sync.

## R10 gate by change class — pick the gate that exercises the change

The R10 principle is EXERCISE, not ceremony: a gate that cannot fail on the
change proves nothing (wasted verification), and a change whose gate never
executed is unproven (the fraud class CLAUDE.md R10 bans). Pick the SMALLEST
gate that genuinely exercises every changed code path — and run it in full.
CLAUDE.md R10 carries the mandate; this matrix is the authoritative detail.

| Change class | Pre-flight | The R10 gate | Tier on a clean pass | Explicitly NOT required |
|---|---|---|---|---|
| **Documentation-only change class** — `*.md` (CLAUDE.md, `plugins/**/SKILL.md`, READMEs, CHANGELOG), comment-only code edits, or a submodule pointer bump to an all-documentation submodule commit; zero behavior change | markdown integrity, link checks | The non-runtime standards: adversarial consistency review, the R5 grep self-test, cross-reference validation, the `pre-commit-gate.sh`/`pre-push-gate.sh` gates | `documentation reviewed` | ANY bed run or image build — beds cannot fail on prose |
| **Hook / workflow scripts** — `.claude/hooks/*.sh`, `.claude/workflows/*.js` | `bash -n` / async-body parse | Execute the changed script live: run the hook directly (paste its output); a workflow whose CONTROL FLOW changed runs against ONE bed matching the change. Prompt-string-only workflow edits: parse + the non-runtime standards | `fully tested and validated` | The full bed fan-out |
| **`charly` Go code** | `go test ./...` + `go vet` + `task build:charly` (R9 freshness + `charly version` check) | `charly check run <bed>` for EACH bed whose kind matches a touched code path: box/candy/pod/DeployTarget mechanism → `check-pod`; `target: local` → `check-local`; VM / k8s → `check-k3s-vm`; a feature surface → its feature bed. Cross-cutting loader / resolver / IR / unified-schema changes → fan EVERY matching bed out CONCURRENTLY via `/verify-beds` (one `charly check run <bed>` per agent; in-spec for that class, not a scope override) | `fully tested and validated` | Beds whose substrate the change cannot reach |
| **Candy / box / pod / vm / k8s / local / android config** | `charly box validate` | Build + run a bed that COMPOSES the changed entity (a candy edit → a bed whose image stacks that candy); when no bed composes it, the R7 sequence on a disposable deploy: build → `charly check box` → deploy → `charly check live` → fresh `charly update` | `fully tested and validated` | Beds that do not compose the changed entity |
| **`iterate:` / ai check config** | `charly box validate` | The affected `iterate:` bed run AS SPECIFIED (see "Flag discipline") | `fully tested and validated` | Unrelated beds |

**Tier on a clean pass — the class fixes the gate; the gate fixes the tier.**
Passing a class's full gate earns the tier in that column. `analysed on a live
system` and `syntax check only` are partial-completion WAYPOINTS for the RUNTIME
classes only — a live invocation ran but no fresh-rebuild R10 → `analysed on a
live system`; only compile / validate / dry-run ran → `syntax check only` (which
FORBIDS commit). The Documentation-only change class has no live runner, so it
has no waypoint: its non-runtime standards either all pass (→ `documentation
reviewed`) or the change is not ready. The tier DEFINITIONS live in CLAUDE.md
"AI Attribution"; this column names which tier each gate earns, it does not
redefine them.

Mixed changes take the UNION of their classes' gates (docs ride along with the
code class in the same commit, at that code class's runtime tier — never
`documentation reviewed`). Class assignment is honest, not aspirational:
a "comment" edit that changes a prompt string an agent executes is
script-text, not docs; a YAML comment is docs, but a YAML field is config. A
submodule pointer bump is documentation only when the bumped submodule commit is
itself all-documentation (`pre-commit-gate.sh` recurses into its `old..new` diff);
a bump integrating submodule code is a code class, at a runtime tier.

## The 10 Testing Standards (READ FIRST — referenced by CLAUDE.md R1–R10)

An earlier agent claimed "cutover complete, all tests pass" after green `go test ./...` runs, then built an image that crash-looped at startup because a Containerfile stage was silently dropped. The unit tests didn't notice — they only exercised YAML loaders. **Unit tests are NOT a substitute for running the service.**

These are the 10 standards referenced in CLAUDE.md's AI attribution tier ("fully tested and validated"). Each is keyed to a CLAUDE.md R-rule. Apply them whenever a change could affect Containerfile generation, OCI labels, init systems, service startup, or deploy code.

0. **Prove every HIGH-RISK assumption BEFORE you edit (RDD — Risk Driven Development)** — the proactive bookend to Standard 10's fresh-rebuild gate. Low-risk orientation ("what does layer X do") is a skill lookup (R0, zero risk); every high-risk assumption — including any a skill or the code merely *asserts*, and above all whether this layer composition at its latest available versions builds / deploys / runs TOGETHER — is proven on a `disposable: true` bed FIRST (`charly check` it). Never accept docs or code as ground truth for a high-risk decision; if the bed disagrees with a skill, the skill is stale — fix it. Standard 0 (validate forward, riskiest-first) and Standard 10 (re-verify on a fresh rebuild) are the two ends of the same loop.

1. **Build a real artifact** (R7) — `charly box build <image>` / `go build` / `charly vm build <vm>`. Not just `go test`. Not just `charly box generate`.
2. **Verify the emitted artifact's content** (R8) — `grep -c supervisord-conf .build/<image>/Containerfile` for any image that uses supervisord; `charly check libvirt domain-xml <vm>` for a VM.
3. **Verify critical OCI / capability labels post-build** (R8) — `charly box labels <ref> --format init` (or any `ai.opencharly.<key>` shorthand) prints the BUILT ref's label and exits non-zero when absent; `charly box labels <ref>` lists the whole capability contract (`/charly-internals:capabilities`). Empty / missing label → the detection path silently returned nil → regression.
4. **Deploy to a DISPOSABLE target** (R10) — NEVER experiment on a resource that doesn't carry `disposable: true`. If no suitable disposable target exists, create one first (`charly bundle add <name> <ref> --disposable` or mark a VM `disposable: true` in `charly.yml` and `charly vm create`). The setup is part of the task. On a disposable target: `charly update <name>` (unattended). On anything else: confirm with the user before any irreversible destroy — EXCEPT preempting a declared-`preemptible:` holder, which is standing-authorized (reversible: graceful stop + guaranteed restore).
5. **Target must reach steady-state** — `charly status <image>` → `running`; `charly check libvirt info <vm>` → state `running`; SPICE socket file exists and accepts a handshake. If the service start-limit is hit, the container is crashing — read `charly logs <image>` and reproduce in a disposable shell (`charly shell <image>`, running the service command manually).
6. **Run the declarative test suite** — `charly check live <image>` full three-section pass against the live container (or `--uri` / `--host` remote equivalent for a remote target).
7. **Verify the deployed binary is the one you built** (R9) — `charly version` on the target matches the expected CalVer, and `charly status <image>` (detail `Image ref:` line; JSON `image_ref`) shows the running container's image ref carries THIS build's CalVer tag, not the prior one. Source-only changes (Syncthing, git push) do NOT update the deployed binary; you must build AND deploy on the target host.
8. **Verify runtime deps are installed via package management** (R9) — on the HOST: `charly doctor` (dependency status), or the host package manager directly (`rpm -q <pkg>` / `pacman -Q <pkg>` — host packages are not charly-managed resources, so the package manager IS their interface); inside a container: `charly cmd <box> 'rpm -q <pkg>'`. Manual installs do NOT count — they won't survive a fresh install on a synced host. Every runtime dep must live in `setup.sh` + `pkg/arch/PKGBUILD`.
9. **Leave the target healthy, not paused/errored** — the final `charly status` (and `charly check libvirt info <vm>` for a VM) is healthy. If the target is in a broken state during exploration, `charly update` it back to the committed config before continuing — never layer experiments on broken state.
10. **Re-verify on a FRESH rebuild after committing the source-level fix** (R10) — `charly update <disposable-target>` one more time from clean, with the new source applied. Run standards 1–9 again against this fresh rebuild. **THIS IS THE ACCEPTANCE GATE.** A fix that works on a hand-patched target but not on a fresh rebuild is a regression waiting for the next unrelated rebuild to wipe your patch. Paste BOTH the exploratory-pass output AND the fresh-rebuild-pass output into the conversation — the user sees both.

### `charly check live parent.child` reaches the actual leaf

`charly check live <parent>.<child>` walks the dotted deployment path through
`ResolveDeployChain` (`charly/deploy_chain.go`) and constructs a multi-hop
`DeployExecutor` chain that lands probes inside the leaf's actual
venue — `command: id` for a pod-in-VM leaf returns the inner pod's user, not
the parent VM's. Live-check and AI-iteration-scoring chain construction go
through the same code path `charly bundle add` uses.
For deeply-nested paths, each segment adds one hop:

```bash
charly check live check-vm                            # → SSHExecutor (1 hop)
charly check live check-vm.inner                      # → SSH + podman exec charly-check-vm_inner (2 hops)
charly check live check-vm.inner.deeper               # → SSH + 2× podman exec (3 hops)
```

Same chain primitive (`NestedExecutor`) used everywhere — `charly bundle
add`, `charly check live`, `charly check run` (AI iteration scoring).

**Exception — a POD leaf nested in a VM delegates its check to the guest.** Because
the host-vantage probes (the protocol verbs cdp/wl/vnc/dbus, which dispatch
out-of-process via their plugin — `candy/plugin-cdp`/`candy/plugin-wl`/`candy/plugin-vnc`/`candy/plugin-dbus` —
against the container resolved on the HOST's podman; and
`${HOST_PORT}` addr/http, resolved via HOST `podman inspect`) cannot
reach a container living in the guest, `charly check live <vm>.<pod>` does NOT
chain-dispatch those per-check (they would SKIP). Instead `runVm` runs
`charly check live <pod>` IN the guest over SSH (`guestNestedCheckCmd` →
`SSHExecutor.RunCapture`), where the nested pod is a DIRECT pod — guest-local
podman, ports on guest localhost, the guest `charly` (installed by
`EnsureCharlyInGuest`) — so cdp/wl/mcp + `${HOST_PORT}` run natively, zero skips.
The guest reads the SAME baked checks from the cp-box'd pod image, so the check
set is identical; the host propagates the guest's report + exit code. A
pod-in-pod or vm-in-vm leaf (no host↔guest container boundary) still uses the
multi-hop chain above. See "Cross-deployment probing" below for the symmetric
authoring surface in a bed's plan (venue-from-position members).

### Specific anti-patterns observed and banned

- **"Unit tests pass → cutover done"** — no. Build + deploy + run + test, every time.
- **"Retested after update → still passing!"** but the pre-update test was against the old running image and the post-update container failed to come up — see the `is not running` error and conclude the update broke it, not that "tests pass in aggregate."
- **"Service start failed, probably a transient"** — no. `A dependency job for X failed` + immediate exit is a real error. Read `charly logs <image>`; `charly shell <image>` reproduces it in a disposable container.
- **"Lifecycle: dev implies disposable"** — no. `disposable: true` is the ONE authorization for autonomous destroy + rebuild. Lifecycle tags are human-facing metadata; they do not authorize anything. See `/charly-internals:disposable`.
- **"This is a dev box so I can just nuke it"** — no. The only authorization for autonomous destroy is the explicit `disposable: true` field on a specific deploy. Everything else requires user confirmation, regardless of hostname.
- **"I tested on the VM I've been patching all afternoon, looks fine"** — incomplete. Run `charly update <disposable-target>` once more from clean and re-verify before claiming success. Without the fresh-rebuild re-verification, your "fix" may be latent on hand-patched state.
- **"I'll test it later / Phase 2"** — no. If the plan said "clean cutover in one PR", don't invent a Phase 2.
- **"The skill/code says so, so I don't need to test it"** — for a HIGH-RISK assumption, no: docs drift and code has bugs; prove it on a disposable bed FIRST (Standard 0). Conversely, do NOT bed-test a LOW-risk orientation fact a skill already states — that's wasted effort. Risk, not documentation status, is the trigger.

If the container needs state that's only available in deploy (volumes, env, tunnel), author the step at `context: [deploy]`. If it needs something at build only (binary path, package presence), author at `context: [build]`. Both contexts must pass for the cutover to be real.

**Confidence tier mapping:** The "fully tested and validated" confidence level in CLAUDE.md's AI-attribution table requires ALL 10 standards met — including Standard 10, the fresh-rebuild re-verification. Anything short of that ships at a lower confidence tier.

## Overview

`charly` ships a goss-inspired declarative testing framework built into the
CLI. Plan steps — each one intent keyword (`run:`/`check:`/`agent-run:`/
`agent-check:`/`include:`) carrying prose, plus at most one verb-position key for
`run:`/`check:` — are authored as an ordered UNNAMED list under `plan:` inside a
`candy:` entity (layer or image) in `charly.yml`; an optional `id:` names a step.
They are **baked into the `ai.opencharly.description` OCI label**
(`LabelDescriptionSet`, which carries the collected plan steps with
`candy:`/`box:`/`deploy` origin annotations) so any pulled image is self-testable
without its source repo. A local `charly.yml` overlay can add steps or override
baked ones by `id:`.

The runner resolves **deploy-time variables** (actual host port mappings,
volume backings, env vars, container IP, DNS) at execution time, so a
check written once works unchanged when `charly.yml` remaps ports.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Pure-box check (disposable, build-context) | `charly check box <image>` | Candy + box sections only, in `podman run --rm` (no host port mappings, no volumes attached) |
| Live full-stack check (running deployment) | `charly check live <name> [-i instance]` | All three sections run via `podman exec` / SSH / nested chain, with full runtime variable resolution |
| R10 bed (full sequence) | `charly check run <bed>` | Build → check image → deploy → check live → fresh update → tear down on a `disposable: true` deploy (ONE bed per invocation). Canonical R10 gate; for a whole roster fan beds out concurrently via `/verify-beds` |
| AI iteration loop | `charly check run <bed>` | Drives an AI through plateau-bounded iterations against a bed carrying an `iterate:` block |
| Validate authored tests at config time | `charly box validate` | Schema, context/variable consistency, id uniqueness |
| Inspect effective spec | `charly box inspect <image>` | JSON includes merged check structure |
| Filter by verb | `charly check live <name> --filter file --filter port` | Repeatable |
| Filter by section | `charly check live <name> --section deploy` | One of: candy / box / deploy |
| Output format | `charly check live <name> --format json\|tap\|text` | Default text |

## Exit codes

`charly check` uses a goss/pytest-style three-way exit convention so automation
(and `charly check run <bed>`) can tell "the thing under test is broken" apart from
"the check couldn't run":

| Code | Meaning |
|---|---|
| `0` | All checks passed. |
| `1` | Command / usage / infra error — bad args, undeclared deploy, container not running, image build/deploy/vm-create failed. The check never produced a pass/fail verdict. |
| `2` | The check RAN and one or more **checks FAILED** (`CheckCheckFailExitCode`). |

`charly check box` / `charly check live` return `2` directly when checks fail.
`charly check run <bed>` propagates `2` when the bed's **check step** (check-image /
check-live) fails on checks, but `1` when an **infra step** (build / deploy /
vm-create) fails — so a broken bed image is distinguishable from a genuine
test failure. When `/verify-beds` fans a roster out, it aggregates the per-bed
exit codes — reporting `2` only when *every* failing bed failed on checks, and
`1` when any bed hit an infra failure. Implementation:
`CheckFailedError` + `CheckCheckFailExitCode` (charly/check_cmd.go), mapped to the
process exit code in `main()` via `errors.As`.

## Image preflight (host-target runs only)

When `charly check run --on-host <name>` (or any `iterate:` entity whose
sandbox resolves to `TargetKindHost`) dispatches the runner, an image
preflight runs FIRST: walk the bed's plan, collect every
distinct step venue's image (per-step `Op.venue`, loader-derived from tree
position) plus the bed's target image, deduplicate, and
ensure each image is present in local podman storage BEFORE handing
off to the host runner.

For each discovered image, the algorithm is:

1. `LocalImageExists(podman, ref)` — short-circuit if already
   present. Idempotent on re-runs.
2. `charly box pull <ref>` — preferred path. Resolves short names via
   `cfg.Images[<name>]`, full registry refs pass-through, remote
   `@github.com/...` refs walk through `ResolveRemoteImage`.
3. `charly box build <name>` — fallback when pull fails AND the
   identifier is a short name resolvable via the project's
   `charly.yml`. Build fallback is local-only; for any non-short
   identifier that fails to pull, the preflight aborts with an
   actionable error.

Failures abort the check BEFORE any plan step runs, so operators see
problems early rather than mid-run.

This is the **only** image-fetch surface in the system: deploys (any
target — `local`, `pod`, `vm`, `k8s`) emit zero image-pull steps. A
`kind: local` template has no `image:` field; image preflight lives on this
verb. Operators with legacy YAML run `charly migrate`. See
`/charly-local:local-spec` "What the deploy does NOT do" and CLAUDE.md
"Deploy fetches NOTHING speculative".

Lives in `charly/check_image_preflight.go`
(`EnsureImagePresent`, `ensureScoreImages`); wired into
`CheckRunCmd.Run` for the `case TargetKindHost:` arm. Pod / VM / k8s
targets carry their own image inside their respective deploy schema
and never trigger the preflight.

## Three primary modes (`charly check box` / `live` / `run`)

The surface is three orthogonal verbs, each named for what it evaluates:

- **`charly check box <image>`** — evaluates the image **artifact** in
  isolation. Spawns a disposable container via `podman run --rm
  <image-ref>` (`ImageExecutor`). Only `check:` steps at
  `context: [build]` run; deploy-context steps are skipped with a clear
  message. The right choice for build-time invariants ("did this
  binary land at this path?", "is this package installed?") where a
  running service would only add noise.

- **`charly check live <name>`** — evaluates a **running deployment**
  (pod / vm / host / k8s; auto-resolved by `<name>` against
  charly.yml). Uses `ContainerExecutor` / `SSHExecutor` /
  `NestedExecutor` (for dotted-path children) + `ResolveCheckVarsRuntime`
  so deploy-context steps see real supervisord state, real
  `HOST_PORT:<N>` mappings (including host-networked containers via
  `HostConfig.NetworkMode` detection), and real in-container env.
  Same dispatcher that powers `charly check live parent.child` for
  pod-in-vm topologies.

- **`charly check run <bed>`** — runs a `disposable: true` R10 deploy (full
  sequence); when the bed carries an `iterate:` block it instead drives
  an AI runner through plateau-bounded iterations. See "AI
  iteration loop semantics" below.

The mode is **explicit in the verb**; there is no autodetect or
implicit fallback. Choose the mode by picking the right verb.

**Which verb/bed proves what (CLAUDE.md R7):** `charly check box` passes on
zero-content stages too — it is NOT a substitute for the generated-artifact
checks (R8). For the R10 gate, pick the disposable bed whose kind matches
what you changed (`check-pod` for the combined box/candy/pod/DeployTarget
mechanism, `check-local`, `check-k3s-vm`, or a feature bed). `charly check run`
on an `iterate:` bed is the multi-hour AI-iteration benchmark, never a quick
gate — the same verb dispatches by whether the entity carries an `iterate:` block.

The banner after `charly check box` reports the image ref:

```
Image: ghcr.io/opencharly/fedora-coder:latest
```

The `meta.Box` short-name (from the `ai.opencharly.box` OCI
label) is used by `charly check live` for the `charly-<image>` container-name
lookup — full image refs like `ghcr.io/opencharly/fedora-coder:latest`
are correctly mapped to `charly-fedora-coder`. Implementation:
`charly/check_cmd.go` `CheckBoxCmd.Run()` and `CheckLiveCmd.Run()`.

## Agent Driven Evaluation (ADE) — `charly box/check feature run` + the agent grader

ADE runs an entity's OWN baked plan (shipped in the
`ai.opencharly.description` OCI label) as acceptance tests. It is named for the
agent that drives the evaluation: an `agent-check:` step is graded by an AI
agent, and the agent's verdicts drive the red→green loop. `charly check box` /
`charly check live` and `charly box/check feature run` read the SAME baked
plan — `charly check box`/`live` run its deterministic `check:` steps, while
`charly box/check feature run` also bind the `agent-check:` (and `agent-run:`)
steps to the agent grader.

### The six-stage loop

| Stage | Who | Command | What |
|---|---|---|---|
| **Specify** | you / an agent | hand-edit the candy's `plan:` list (or `charly box set candy.<name>.plan ...`) | Author the `description:` string + `plan:` steps on the CANDY that provides the behaviour (it bakes into every box that composes the candy — R3). |
| **Bind** | author (implicit) | `charly feature pending <entity>` lists the agent-graded steps | Use a `check:` step (inline verb) → deterministic; use an `agent-check:` step (prose) → agent-graded. |
| **Run** | you / CI | `charly box feature run <image>` / `charly check feature run <deployment>` | Execute the plan; per-step pass/fail + grader evidence. |
| **Iterate** | you / an agent | edit + re-run, OR `charly check run <bed>` (an `iterate:` bed) | Drive red→green by hand, or let the plateau-bounded AI loop write the code until the `check:` steps pass. |
| **Bake** | the build | `charly box build` | `description:` + plan steps bake into `ai.opencharly.description`; runs source-less against a pulled image. |
| **Gate** | R10 | `charly check run <bed>` | Runs the bed image's deterministic `check:` steps — every candy ships them (ADE authoring is mandatory: `charly box validate` requires a non-empty `description:` string and at least one deterministic `check:` step). The live agent grader via `charly check feature run` stays opt-in. |

### The BIND contract — a step binds to its verifier BY SHAPE

```yaml
# candy/<name>/charly.yml — description: + the ordered plan: list, all inline
# in the candy body (the ONE flat operational sequence)
dashboard:
    candy:
        description: Dashboard          # the candy's purpose; first line = summary
        plan:
            - check: the page title is Dashboard   # inline verb → DETERMINISTIC
              id: dashboard-title
              cdp:
                  method: eval
                  expression: document.title
            - agent-check: the chart looks populated, not empty   # PROSE-ONLY → agent-graded
```

A `check:` step carries an embedded probe verb (`file`/`http`/`command`/`cdp`/
`mcp`/…) and runs that check deterministically. An `agent-check:` step carries
only prose and binds to the agent grader. `charly feature pending` lists every
`agent-run:`/`agent-check:` step so an author sees the agent-graded work.

### The two run verbs

- **`charly box feature run <image>`** — build context. A disposable container
  (`podman run --rm` per check), deterministic `check:` steps only. An
  `agent-check:`/`agent-run:` step has no stable target to probe, so it reports
  unbound (advisory skip; `--strict` fails it). Resolves the image against local
  storage (never `charly.yml`), like `charly check box`.
- **`charly check feature run <deployment>`** — deploy context. Against a running
  image-backed (pod) deployment; deterministic `check:` steps run their checks and
  `agent-check:` steps bind to the **agent grader** (unless `--no-agent`). Flags:
  `-i/--instance`, `--format text|json|tap|junit`, `--tag <expr>`,
  `--agent <name>`, `--timeout <dur>`, `--no-agent`, `--strict`.

Exit codes follow the 0/1/2 convention (a step fail → exit 2 via
`CheckFailedError`; an infra error → 1). No plan baked → a no-op pass.

### The agent grader contract

For a prose-only step (when grading is enabled), the runner spawns the
configured `kind: agent` CLI ONCE (bounded — never the plateau loop), handing it the
entity's `description:`, the step's prose, the live
target name, and the instruction that it MAY probe via `charly cmd <target> …`,
`charly check live <target> --filter <verb>`, `charly status <target>`. The agent returns a
single-line JSON verdict `{"verdict":"pass|fail","evidence":"…"}`; the runner
parses it (plain or `stream-json`) into a pass/fail with evidence. An
unparseable / timed-out / launch-failed grader is a **FAIL** with the raw output
— never a silent pass. The grader wall-clock cap is `--timeout` → the ai entry's
`timeout:` → a 5m default. Which agent: `--agent <name>` → the sole configured `agent:`
entry → an explicit "specify --agent" error.

`--no-agent` is the deterministic-only mode (CI): `agent-check:` steps report
`unbound` (visible, never silently green). The unattended `charly check run <bed>`
gate runs `charly check feature run <bed> --no-agent` so a bed stays deterministic and
free; exercise the live grader with an explicit `charly check feature run <name>`.

### Worked example (end to end)

```bash
# 1. Author plan steps on the layer that provides the behaviour.
$EDITOR candy/web-layer/charly.yml    # add a `check:` step (cdp: eval) +
                                      # an `agent-check:` prose step

# 2. See the agent-graded steps.
charly feature pending candy:web-layer

# 3. Build → run build-context acceptance (deterministic steps).
charly box build web
charly box feature run web

# 4. Deploy, then run deploy-context acceptance with the agent grader.
charly start web
charly check feature run web                # agent-check steps agent-graded against the live pod
charly check feature run web --no-agent     # deterministic-only (CI): agent-check steps report unbound
```

Implementation: `charly/check_feature_run.go` (the verbs), `charly/check_feature_grader.go`
(`AgentGrader` + `RunAIOnce` + `parseVerdict`), the `Runner.Grader` dispatch in
`charly/description_run.go`, and `charly/description_cmd.go` (`charly feature
list/pending/validate`). The plan engine (`RunPlan`) and target
resolution are shared with the harness loop and `charly check box`/`live` (R3).

## Live-container verbs — ALL served out-of-process

There are **no in-core `charly check <verb>` host subcommands**: every
live-container probe verb is served out-of-process by its plugin candy and
reached ONLY as a declarative step. `wl` was the LAST live-container verb
compiled into charly — after its move to `candy/plugin-wl`, ZERO check verbs are
in-core. The `charly check` command tree is now the three primary modes +
`feature` + the check-run management subcommands (`box`/`live`/`run`/`feature`,
`list`/`report`/`note`/…) — nothing else.

Each live-container verb (`cdp:`/`wl:`/`vnc:`/`dbus:`/`mcp:`/`record:`/`kube:`/
`adb:`/`appium:`/`spice:`/`libvirt:`) is authored as a declarative step and
dispatched through the provider registry exactly like a built-in verb
(`ResolveVerb` → the out-of-process gRPC provider → `Provider.Invoke`); run a
candy's baked steps with `charly check live <image> --filter <verb>`. `libvirt`
(served by `candy/plugin-vm`) and `kube`/`adb`/`appium` are additionally surfaced
under `charly check` at runtime via `attachNestedCheckPlugins`. Authoring never
says `plugin: <verb>` — you write `wl: screenshot`, `libvirt: info`, etc. The
per-verb skill + serving plugin are listed in the Related-skills note below.

Because no live-container verb is a host subcommand any more, an image's name can
never collide with one — `charly check live <name>` resolves the image
unambiguously.

## Authoring: the plan (the ordered `plan:` list)

Every step is an entry in the entity's ordered `plan:` list — ONE intent keyword
(`run:`/`check:`/`agent-run:`/`agent-check:`/`include:`) carrying prose, plus —
for `run:`/`check:` — at most one verb-position key (a builtin install verb, or
the plugin-verb sugar `<word>: <input>`: a map is the verb's input verbatim,
holding the verb-specific attributes; a scalar is the verb's primary-field
shorthand) and the shared step modifiers as siblings. An optional `id:` names a
step (reports + overlay merging), mirroring `candy/redis/charly.yml`. `run:`
steps ARE the install timeline; `check:` steps are the deterministic idempotent
probes `charly check`/`charly check live` run.

### Gold-standard pattern (redis candy)

```yaml
# candy/redis/charly.yml — the ordered plan: list inline in the candy body.
redis:
    candy:
        version: 2026.144.1531
        description: A Redis-compatible key-value server supervised on 127.0.0.1:6379
        plan:
            # Build-context check: — run inside the built image via `podman run --rm`.
            - check: the redis-server binary is installed
              file:
                  file: /usr/bin/redis-server
                  exists: true
            - check: the redis-cli binary is installed
              file:
                  file: /usr/bin/redis-cli
                  exists: true
            - check: the providing package is installed
              package:
                  package: valkey-compat-redis   # see "Authoring Gotchas" on renames
                  package_map:
                      arch: valkey
                  installed: true
            # Runtime check: — HOST_PORT:N resolves to the effective port mapping, so
            # the same step works whether the deploy publishes 6379:6379 or 16379:6379.
            - check: redis answers ping over the published port
              id: redis-responds
              context: [runtime]
              stdout: PONG                       # shared matcher — a step-level sibling
              command:
                  command: redis-cli -h 127.0.0.1 -p 6379 ping
                  in_container: true
            - check: the redis port is reachable from the host
              id: redis-port-open
              context: [runtime]
              addr: 127.0.0.1:${HOST_PORT:6379}  # scalar sugar: addr's primary field
```

The five `check:` steps cover: binary existence, package identity, a functional
live probe, and raw TCP reachability. Adopt this shape for any primary
service layer.

### Cross-distro package names (`package_map:`)

The `package:` verb chains `rpm -q || dpkg -s || pacman -Q` with a single
literal name, so a test that works on Fedora (`openssh-server`) fails on
Arch (where the package is just `openssh`). `package_map:` is the
authoring hook: the first key that matches any of the image's
`distro:` tags wins; otherwise the `package:` scalar is used as the
fallback. Source: `charly/checkrun_verbs.go:resolvePackageName` + the
`Runner.Distros` field wired from `meta.Distro` at both test entry
points.

```yaml
# candy/sshd/charly.yml — cross-distro authoring (a plan: step; the package-verb
# fields, package_map included, live INSIDE the package input map)
plan:
    - check: the openssh-server package is installed
      id: openssh-server-package
      package:
          package: openssh-server          # Fedora / Debian default
          package_map:
              arch: openssh                # Arch ships the metapackage as 'openssh'
              fedora: openssh-server
              fedora:43: openssh-server    # explicit version tag — matches before 'fedora'
          installed: true
```

Tag priority: entries in `distro:` are in priority order (e.g.
`["fedora:43", fedora]`), so `package_map:` can be keyed on either the
version-specific or the family tag, and the more-specific tag wins
naturally. An empty-string map value falls through to the next tag
(see `TestResolvePackageName` in `charly/checkrun_verbs_test.go`).

### Verb catalog (goss-parity feature set)

Every verb-exclusive attribute below lives INSIDE the verb's input map
(`file: {file: /x, exists: true}`), validated by the plugin's OWN served CUE
schema; a scalar value is the verb's primary-field shorthand (`file: /x`,
`command: id`, `cdp: status`, …). The shared step modifiers and the
`stdout`/`stderr`/`exit_status` matchers stay step-level siblings.

| Verb | Input attributes (inside the verb map) | Notes |
|------|---------------------|-------|
| `file` | `file` (primary), `exists`, `mode`, `owner`, `group_of`, `filetype`, `contains`, `sha256` | `group_of` (not `group`) — `group` is a reserved kind word, so the owning-group attribute is spelled `group_of` (the getent-group probe verb is `unix_group`) |
| `package` | `package` (primary), `installed`, `version`, `package_map` | Tries rpm / dpkg / pacman — exact match on installed name (see gotchas) |
| `service` | `service` (primary), `running`, `enabled` | Supervisord first, then systemd |
| `port` | `port` (primary), `listening`, `ip`, `reachable` | **`listening` needs `ss`/`netstat` inside the container** — absent from minimal images |
| `process` | `process` (primary), `running` | **Needs `pgrep`** — absent from minimal images |
| `command` | `command` (primary), `in_container` | Default runs via `podman exec`; set `in_container: false` to run from host. Assert via the shared `exit_status`/`stdout`/`stderr` step matchers |
| `http` | `http` (primary URL), `status` (int, single value), `body`, `headers`, `method`, `request_body`, `allow_insecure`, `no_follow_redirects`, `ca_file`, `timeout` | Host-side under `charly check live`; curl-in-container under `charly check box` |
| `dns` | `dns` (primary), `resolvable`, `addrs`, `server` | Host resolver for `charly check live`; `getent hosts` for `charly check box` |
| `user` | `user` (primary), `uid`, `gid`, `home`, `shell` | `getent passwd` |
| `unix_group` | `unix_group` (primary), `gid`, `groups` | `getent group` |
| `interface` | `interface` (primary), `mtu`, `addrs` | `ip -o addr show` |
| `kernel-param` | `kernel-param` (primary), `value` (scalar or matcher) | `sysctl -n` |
| `mount` | `mount` (primary), `mount_source`, `filesystem`, `opts` | `findmnt` |
| `addr` | `addr` (primary), `reachable`, `timeout` | Pure Go-native `net.DialTimeout` for `charly check live`; `nc` for `charly check box` |
| `matching` | `matching` (primary), `contains` | Pure in-process value matching — no target probe |
| `cdp` | `method` (primary: status/list/eval/text/html/url/axtree/screenshot/open/click/type/raw/wait/coords + spa-*) + method-specific fields (`tab`, `expression`, `url`, `selector`, `text`, `artifact`, `x`, `y`, `http_method` for `raw`) + `artifact_min_bytes` | **Deploy-context only.** Dispatches out-of-process via `candy/plugin-cdp` (no host subcommand). See Live-container verb catalog below. |
| `wl` | `method` (primary: screenshot/status/click/type/key/key-combo/mouse/scroll/drag/clipboard/toplevel/windows/focus/close/geometry/xprop/atspi/exec/resolution + overlay-*/sway-*) + method-specific fields (`x`, `y`, `text`, `key`, `combo`, `target`, `action`, `command`, `artifact`) | **Deploy-context only.** Dispatches out-of-process via `candy/plugin-wl` (no host subcommand; includes the `sway-*` and `overlay-*` nested methods). See Live-container verb catalog below. |
| `dbus` | `method` (primary: list/call/introspect/notify) + method-specific fields (`dest`, `path`, `member` — the fully-qualified interface.Method a `call` invokes, `arg`, `text`) | **Deploy-context only.** Dispatches out-of-process via `candy/plugin-dbus` (no host subcommand); EXEC-based, driving the venue's session bus with `gdbus`. |
| `vnc` | `method` (primary: status/screenshot/click/mouse/type/key/rfb/passwd) + method-specific fields (`x`, `y`, `text`, `key`, `artifact`) | **Deploy-context only.** Dispatches out-of-process via `candy/plugin-vnc` (no host subcommand); the host pre-resolves the RFB endpoint for pod AND vm targets. See Live-container verb catalog below. |
| `mcp` | `method` (primary: ping/servers/list-tools/list-resources/list-prompts/call/read) + method-specific fields (`tool`, `uri`, `input`, `mcp_name`) | **Deploy-context only.** Speaks `github.com/modelcontextprotocol/go-sdk` to any `mcp_provide` endpoint. See "Method allowlist — mcp" below. |

> **STRICT RULE — a step verb (or Op modifier) MUST NEVER be spelled like a reserved KIND word.** Kinds (`candy`, `pod`, `vm`, `k8s`, `local`, `android`, `group`, …) live ONLY at a config EDGE — the opening discriminator of a top-level node or a tree-child node — never as a key in the middle of a step. A new probe verb that would collide with a kind word MUST pick a non-colliding spelling (the `k8s`/`group` probe verbs were renamed to `kube`/`unix_group` for exactly this reason). This is machine-enforced by `sdk/spec` `TestNoKindWordAsStepVerb` + `TestNoKindWordAsOpModifier` — adding a colliding verb fails the build.

### Shared modifiers

| Field | Purpose |
|-------|---------|
| `id` | Optional stable identifier. Enables `charly.yml` to override by `id`. Unique per section per image. |
| `description` | Human-readable label for reports. |
| `skip: true` | Always skip this check (reported but doesn't fail the run). |
| `exclude_distro: [<tag>, ...]` | Skip the check when any of the image's `distro:` tags matches an entry. Use for probes that only apply on some distros (e.g. `file: /usr/bin/fastfetch` is valid on Fedora/Arch/Debian but fastfetch is dropped from Ubuntu 24.04's noble main). Matched against the image's full distro list (`["ubuntu:24.04", "ubuntu", "debian"]`), so either `ubuntu:24.04` or `ubuntu` matches. See `charly/checkspec.go:Op.ExcludeDistros` and `charly/checkrun.go:runOne`. |
| `timeout: "5s"` | Per-check timeout (http, addr). |
| `context: [build\|deploy\|runtime]` | Which contexts the step runs in (a list). Build steps run in `charly check box`; deploy/runtime steps need a live deployment. |

#### `exclude_distro:` worked example

```yaml
plan:
    - check: the fastfetch binary is installed (skipped on Ubuntu)
      id: fastfetch-binary
      exclude_distro:
          - ubuntu
      file:
          file: /usr/bin/fastfetch
          exists: true
```

On `ghcr.io/opencharly/ubuntu-coder:latest` this reports `skipped (excluded on distro "ubuntu")` instead of `failed`. On any other image it runs normally. Prefer this over dropping the test entirely — it keeps the guard in place for Fedora/Arch/Debian and documents why Ubuntu is special.

**Compared to `package_map:`** — `package_map:` changes what the test *probes for* per distro (same semantic, different package name). `exclude_distro:` skips the check entirely — use it when the functionality genuinely doesn't exist on a given distro.

### Matcher forms

Any `MatcherList` attribute (`stdout`, `stderr`, `body`, `headers`,
`contains`, `opts`, `value`) accepts three shapes — picked by yaml.v3
at parse time:

```yaml
stdout: PONG                         # scalar  → [{equals: PONG}]
stdout: [PONG, READY]                # list    → [{equals: PONG}, {equals: READY}]
stdout:
  - equals: PONG                     # operator map
  - contains: ["ready", "ok"]
  - matches: "^[A-Z]+$"
  - not_contains: "error"
```

Supported operators: `equals`, `not_equals`, `contains`, `not_contains`,
`matches`, `not_matches`, plus `lt`/`le`/`gt`/`ge` (numeric, added as
verbs need them).

**`status:` is NOT a MatcherList** — it's a plain `int` on the `http`
verb. One code per test. See Authoring Gotcha #2.

### Live-container verb catalog: `cdp`, `wl`, `dbus`, `vnc`, `mcp`

None of these verbs has a host `charly check` subcommand — each dispatches
out-of-process via its plugin (`candy/plugin-cdp`, `candy/plugin-wl`,
`candy/plugin-dbus`, `candy/plugin-vnc`, `candy/plugin-mcp`; parallel to the
`kube:`/`spice:`/`adb:`/`appium:` plugin verbs).
The `vnc` plugin covers pod AND vm targets — the host pre-resolves the RFB endpoint
(pod port-5900 or a VM's libvirt VNC via bridge/tunnel) and the plugin dials it.
Every live-container
operation (browser automation, Wayland input/screenshot, D-Bus calls, VNC
framebuffer capture, MCP protocol probes) is authorable as a declarative step.
All five are **deploy-context only** — they need a running container with port
mappings; `charly box validate` rejects them in build context, and `charly check
box` skips them at runtime with a clear message.

**Assertion semantics:** the runner dispatches the method to the out-of-process
plugin (`candy/plugin-cdp`, `candy/plugin-wl`, `candy/plugin-vnc`,
`candy/plugin-dbus`, `candy/plugin-mcp`), which captures stdout/stderr/exit and
feeds the output through the existing matcher pipeline. Queries
(status/list/eval/text/html/url/axtree/screenshot/…) produce assertable output.
Side-effect actions (click/type/open/close/…) pass when they exit 0 — follow them
with a query check to verify the effect.

**No state chaining:** there's no framework-managed variable to
carry a tab ID or window handle from one check to the next. Authors rely
on conventions (new tabs are usually ID 1) and inspect state via
follow-up `cdp: list` checks if needed.

#### Method allowlist — `cdp` (15 methods + 6 SPA-nested)

Queries: `status`, `list`, `url`, `text`, `html`, `eval`, `axtree`,
`coords`, `raw`, `wait`, `screenshot`.
Actions: `open`, `close`, `click`, `type`.
SPA-nested (selkies coordinate-scaling / passthrough input):
`spa-status`, `spa-click`, `spa-type`, `spa-key`, `spa-key-combo`,
`spa-mouse`.

```yaml
plan:
    - check: the CDP endpoint is reachable
      id: cdp-up
      cdp: status                   # scalar sugar == {method: status}
      stdout:
          equals: ok

    - check: the page title is Dashboard
      id: cdp-page-title
      cdp:
          method: eval
          tab: "1"
          expression: "document.title"
      stdout: "Dashboard"

    - check: a non-empty CDP screenshot is captured
      id: cdp-screenshot-valid
      cdp:
          method: screenshot
          tab: "1"
          artifact: /tmp/cdp.png
          artifact_min_bytes: 10000   # PNG must be non-empty
```

#### Method allowlist — `wl` (22 top-level + 4 overlay + 12 sway)

Queries: `screenshot`, `status`, `toplevel`, `windows`, `geometry`,
`xprop`, `atspi`, `clipboard`.
Actions: `click`, `double-click`, `mouse`, `scroll`, `drag`, `type`,
`key`, `key-combo`, `focus`, `close`, `fullscreen`, `minimize`, `exec`,
`resolution`.
Overlay-nested: `overlay-list`, `overlay-status`, `overlay-show`,
`overlay-hide`.
Sway-nested: `sway-tree`, `sway-workspaces`, `sway-outputs`, `sway-msg`,
`sway-focus`, `sway-move`, `sway-resize`, `sway-kill`, `sway-floating`,
`sway-layout`, `sway-workspace`, `sway-reload`.

```yaml
plan:
    - check: a non-empty desktop screenshot is captured
      id: wl-desktop-captured
      wl:
          method: screenshot
          artifact: /tmp/wl.png
          artifact_min_bytes: 10000

    - check: at least one toplevel window is present
      id: wl-has-windows
      wl: toplevel
      stdout:
          matches: "."      # at least one line of output

    - check: sway reports workspace "1"
      id: wl-sway-has-workspace-1
      wl: sway-workspaces
      stdout:
          contains: '"name":"1"'
```

#### Method allowlist — `dbus` (4 methods)

Queries: `list`, `call`, `introspect`.
Actions: `notify`.

```yaml
plan:
    - check: the Notifications service is registered on the bus
      id: dbus-notifications-registered
      dbus: list
      stdout:
          contains: "org.freedesktop.Notifications"

    - check: the Notifications service answers GetCapabilities
      id: dbus-get-capabilities
      dbus:
          method: call
          dest: org.freedesktop.Notifications
          path: /org/freedesktop/Notifications
          member: org.freedesktop.Notifications.GetCapabilities
      stdout:
          contains: body
```

#### Method allowlist — `vnc` (8 methods)

Queries: `status`, `screenshot`, `rfb`.
Actions: `click`, `mouse`, `type`, `key`, `passwd`.

```yaml
plan:
    - check: the VNC endpoint is reachable
      id: vnc-up
      vnc: status
      stdout:
          equals: ok

    - check: a non-empty VNC framebuffer is captured
      id: vnc-framebuffer-captured
      vnc:
          method: screenshot
          artifact: /tmp/vnc.png
          artifact_min_bytes: 5000
```

#### Method allowlist — `mcp` (7 methods)

Queries: `ping`, `servers`, `list-tools`, `list-resources`, `list-prompts`,
`read`.
Actions: `call`.

The `mcp` verb speaks the Model Context Protocol to any server advertised
via `mcp_provide`. URL resolution is automatic — the runner reads the
image's `ai.opencharly.mcp_provide` OCI label, substitutes
`{{.ContainerName}}`, runs the entries through `podAwareMCPProvides`, and
then rewrites the host portion to `127.0.0.1:<published-host-port>` using
the same port-mapping data that powers `${HOST_PORT:N}`. No URL argument
is needed in YAML.

Transport dispatch: `transport: http` (or empty) → Streamable HTTP;
`transport: sse` → SSE. Anything else is rejected at dial time.

Disambiguation: if an image declares multiple `mcp_provide` entries,
add `mcp_name: <server>` on the check; otherwise the single entry
auto-picks.

```yaml
plan:
    - check: the MCP server answers a ping
      id: mcp-ping
      context: [deploy]
      mcp: ping
      timeout: 10s              # optional; default 30s

    - check: the MCP server lists its notebook tools
      id: mcp-list-tools
      context: [deploy]
      mcp: list-tools
      stdout:
          - contains: insert_cell   # plaintext "name\tdescription" per line
          - contains: execute_cell

    - check: calling list_notebooks succeeds (no IsError)
      id: mcp-call-tool
      context: [deploy]
      mcp:
          method: call
          tool: list_notebooks  # required
          input: "{}"           # optional JSON arg blob
      exit_status: 0            # assert no IsError

    - check: reading a resource returns a non-empty body
      id: mcp-read-resource
      context: [deploy]
      mcp:
          method: read
          uri: file:///tmp/example.txt
      stdout:
          - matches: "."        # non-empty body
```

There is **no** host `charly check` subcommand for `mcp`: it is a
declarative-only check verb served out-of-process by `candy/plugin-mcp` (parallel
to `kube:`/`spice:`/`adb:`/`appium:`). Exercise it by running the candy's baked
`mcp:` steps against a live deployment — `charly check live <image> --filter mcp` —
or author the steps above. For multi-server images the `--name` flag is the
declarative `mcp_name:` modifier; the full verb reference (methods, URL rewriting,
port-publishing gotcha, validator rules) lives in `/charly-build:charly-mcp-cmd`.

Output format: tab-separated plaintext (one record per line) so matchers
can `contains:` without JSON decoding. `list-tools` emits
`<name>\t<description>`; `list-resources` emits `<uri>\t<name>\t<mime>`;
`call` emits the concatenated `TextContent` payloads; `ping` emits `ok`.

#### Artifact-validation modifiers

For artifact-producing methods (`cdp: screenshot`, `wl: screenshot`,
`vnc: screenshot`, `libvirt: screenshot`, `spice: screenshot`,
`record: stop`), set `artifact: <path>` to tell `charly` where to write the
output AND any combination of the modifiers below to assert the
artifact's correctness post-run.

- **`artifact_min_bytes: <N>`** — assert the file is at least N bytes
  after the run. Guards against zero-byte files. Cheap (`os.Stat`
  only).
- **`artifact_min_dimensions: WxH`** — assert decoded image width and
  height are each at least the given values. Reads only the PNG/JPEG
  header via `image.DecodeConfig`, so essentially free. Catches "the
  screenshot ran but the compositor produced 320×240 instead of the
  expected 1920×1080".
- **`artifact_not_uniform: true`** — assert the image is not uniformly
  one color. Decodes the full image and samples 100 pixels at
  deterministic stride positions; fails if every sampled pixel has
  the same RGBA. Catches the failure mode `artifact_min_bytes` is
  blind to: a 100KB all-black PNG passes the byte check but fails
  this one. Use on every screenshot probe where "the image has real
  content" matters.
- **`artifact_min_cast_events: <N>`** — for asciinema `.cast`
  artifacts (e.g. `record: stop` in terminal mode): validates the
  first line is the asciinema v2 header and counts at least N event
  lines after it. Catches "the recording started and stopped but
  captured nothing because nothing was typed".

```yaml
plan:
    # Combined screenshot validity assertion — bytes + dimensions + content.
    - check: the CDP screenshot is a real, non-uniform image
      id: cdp-screenshot-real
      cdp:
          method: screenshot
          tab: "1"
          artifact: /tmp/cdp.png
          artifact_min_bytes: 5000
          artifact_min_dimensions: 800x600
          artifact_not_uniform: true

    # Recording validity — bytes + event count.
    - check: the terminal recording captured real events
      id: record-cast-has-events
      record:
          method: stop
          artifact: /tmp/session.cast
          artifact_min_bytes: 200
          artifact_min_cast_events: 5
```

The four modifiers are independent — set just the one you need or
combine all four for the strongest "the artifact is real" assertion.
Failure messages identify the specific artifact and the specific
threshold that wasn't met.

## Authoring Gotchas (learned the hard way)

These are the non-obvious issues that surface only when you run the tests
against real containers. Skim before writing new checks.

### 1. Host-side deploy tests: `127.0.0.1:${HOST_PORT:N}`, NOT `${CONTAINER_IP}:${HOST_PORT:N}`

In rootless podman, the container's pod-network IP (e.g. `10.89.0.x`) is
not routable from the host. `${HOST_PORT:N}` resolves to a port on the
host's loopback that forwards into the container. Combining them is
nonsense:

```yaml
# ❌ WRONG — 10.89.0.x:HOST_PORT is unreachable from either side.
addr: ${CONTAINER_IP}:${HOST_PORT:8080}

# ✓ RIGHT — host-side access via the forwarded port.
addr: 127.0.0.1:${HOST_PORT:8080}

# ✓ ALSO RIGHT — in-container, using the container port directly.
command: curl -fsS http://127.0.0.1:8080/health
in_container: true
```

Use `${CONTAINER_IP}` only from inside another container in the same pod.

### 2. `http` status is a single int — no lists

```yaml
# ❌ WRONG — yaml unmarshals a list to int fails with "cannot unmarshal !!seq"
status: [200, 301, 302]

# ✓ RIGHT — pick the most-likely code. Or author multiple tests.
status: 200
```

For endpoints that return 400/401 when probed without auth (MCP servers,
API endpoints), `status: 400` is a legitimate "endpoint exists and refuses
empty input" check.

### 3. `pgrep`, `ss`, `nc` are NOT in minimal images

The `process:`, `port: listening`, and `nc`-based command tests silently
fail on images that skip `procps-ng` / `iproute` / `ncat`. Portable
alternatives:

| Intent | Portable alternative |
|--------|----------------------|
| "supervisord is running" | `command: supervisorctl pid; exit_status: 0` (in_container) |
| "some program under supervisord" | `service: <name>; running: true` |
| "port N listening in-container" | `command: curl -fsS http://127.0.0.1:N/<route>; in_container: true` |
| "port reachable from host" | `addr: 127.0.0.1:${HOST_PORT:N}; reachable: true` (Go-native dial) |

### 4. `supervisorctl status` exits 3 when ANY program is non-RUNNING

Layers like `hermes` declare `autostart=false` programs (e.g.
`hermes-whatsapp`), which leaves them STOPPED. `supervisorctl status`
returns exit 3 — fails `exit_status: 0` checks.

```yaml
# ❌ BRITTLE — fails if any program is autostart=false.
command: supervisorctl status
exit_status: 0

# ✓ ROBUST — `pid` asks for supervisord's own PID, 0 iff the socket
# responds.
command: supervisorctl pid
exit_status: 0
in_container: true
```

### 5. Know which stream a `--version`-style command writes to

`charly version` writes to **stdout** (via `fmt.Println`) — the canonical
`candy/charly/charly.yml` test asserts a `stdout:` matcher.

```yaml
plan:
    - check: charly version prints a CalVer to stdout
      id: charly-version
      command: /usr/local/bin/charly version
      exit_status: 0
      stdout:
          - matches: "[0-9]{4}\\.[0-9]+"
```

**But other tools genuinely write to stderr** — `ssh -V`, `openssl version`,
some `*-config --version` scripts. Always probe first
(`charly cmd <image> '<cmd> 2>&1 >/dev/null'` — if the output shows up here
it was stderr; if silent, it's stdout). See also the `ssh-version`
check in `candy/ssh-client/charly.yml` which IS a real stderr case.

### 6. Drop `$` anchor in `matches:` regexes on command output

Command stdout typically ends with `\n`. Go's `regexp` treats `$` as
end-of-input (not end-of-line by default), so `\.ipynb$` won't match
`path.ipynb\n`. Drop the anchor:

```yaml
# ❌ WRONG — fails because trailing newline
stdout:
  - matches: "\\.ipynb$"

# ✓ RIGHT — substring match is usually what you want
stdout:
  - matches: "\\.ipynb"
```

### 7. `${VAR:-default}` is NOT supported by charly's resolver

charly's variable resolver accepts `${IDENT}` only — no bash-style defaults,
no parameter expansion. An unresolved variable is reported as a
`unresolved variables: <name>` SKIP.

```yaml
# ❌ Parsed as a single var name; reported as unresolved if not set
command: psql -U ${POSTGRES_USER:-postgres}

# ✓ Plain env-var reference; resolves from the container's environment
# in the deploy context. For a true default, set it in the layer's `env:`.
command: psql -U ${POSTGRES_USER}
```

### 8. Fedora 43 package renames — query the installed name, not the dnf request

The `package:` verb does exact string equality against the rpm
database, not the dnf install request. When dnf resolves a virtual
provides, the test must name the actual installed package.

| dnf request | Installed name on Fedora 43 |
|-------------|-----------------------------|
| `redis` | `valkey-compat-redis` |
| `liberation-fonts` | `liberation-sans-fonts` (+ `-serif-fonts`, `-mono-fonts`) |

Always verify with `charly shell <image> -c 'rpm -qf /path/to/binary'`.

### 9. Volume paths don't exist at build context

`/workspace`, `${VOLUME_CONTAINER_PATH:name}`, and similar paths
are provisioned by `charly config` at deploy time. A build-context step on
them fails in `charly check box` because the mount isn't attached.

```yaml
# ❌ Fails under `charly check box` — workspace isn't mounted
- check: the workspace directory exists
  id: workspace-dir
  file:
      file: /workspace
      filetype: directory

# ✓ context: [deploy] so it runs only against live containers
- check: the workspace directory exists
  id: workspace-dir
  context: [deploy]
  file:
      file: /workspace
      filetype: directory
```

### 10. Disposable tests run as the image's default USER — not root

`charly check box` runs `podman run --rm <image>` with the image's USER
directive (typically uid 1000 for containers). Root-only files
(e.g. `/etc/sudoers.d/*` is root:root 0750) report as "missing" because
the user can't traverse the parent directory.

```yaml
# ❌ Reports "exists=false" even though the file IS there (0750 dir)
- check: the charly-user sudoers drop-in exists
  id: sudoers-charly-user
  file:
      file: /etc/sudoers.d/charly-user
      exists: true

# ✓ Verify the semantic (can I sudo?) instead of the file bit
- check: the user can sudo without a password
  id: sudoers-charly-user
  command: sudo -n -l
  exit_status: 0
  stdout:
      - contains: "NOPASSWD"
```

### 11. **Bootc images keep USER=root** — tests must cover both modes

Gotcha 10 flips for bootc. `charly/generate.go` deliberately omits the final `USER <uid>` directive on bootc images because systemd (PID 1 in a bootc VM) manages user sessions via login, so the container's own USER directive is irrelevant. Result: the same `charly check box` that runs as uid 1000 in a container runs as **uid 0** in a bootc image.

That breaks any test that assumes the user-context default. A `sudo -n -l` check that expects `NOPASSWD` in the output works for non-bootc (USER=1000 → sudo lists the user's NOPASSWD rule) but fails for bootc (USER=0 → sudo prints root's Defaults block, which doesn't contain the literal string `NOPASSWD`). Same failure mode for any `test -f ~/.config/foo` that depends on `$HOME=/home/user`.

The fix: drop into `user` explicitly when running as root, stay as-is otherwise. Use **`runuser -u user -- <cmd>`** as the bridge — it's portable across util-linux versions and preserves stdout:

```yaml
# Dual-mode: container (USER=1000) AND bootc (USER=root) both pass
- check: the user can sudo without a password (container AND bootc)
  id: sudoers-charly-user
  command: |
      if [ "$(id -u)" = "0" ]; then
        runuser -u user -- sudo -n -l
      else
        sudo -n -l
      fi
  exit_status: 0
  stdout:
      - contains: "NOPASSWD"
```

**Don't use `runuser -l user -s /bin/bash -c '…'`.** On Arch's util-linux
(2.42+), `runuser -l … -c` swallows the wrapped command's stdout when
the shell is a login shell — reproduced: `runuser -l user -s /bin/bash
-c 'sudo -n -l'` prints nothing and exits 0; `runuser -u user -- sudo
-n -l` prints the full NOPASSWD listing. This bit the earlier shipping
form of the test; the sshd candy now uses `-u … --`.

Worked example: `/charly-coder:sshd` ships exactly the `-u user --` pattern. Alternative: give the step `context: [deploy]` so it runs against a live container where you control the user-switch externally.

### 12. **`charly check box <short-name>` is ambiguous with multiple CalVer tags** — use the full registry ref

`charly check box` resolves its positional argument against **local podman storage**, not `charly.yml`. When the host has accumulated many CalVer tags for the same image (a normal consequence of iterative `charly box build` runs), the short form errors out:

```
charly: error: ambiguous short name "openclaw-desktop" in local storage;
           candidates: ghcr.io/opencharly/openclaw-desktop:latest,
           ghcr.io/opencharly/openclaw-desktop:2026.109.1418,
           ... Re-run with a full ref.
```

Use the fully-qualified registry ref:

```bash
charly check box ghcr.io/opencharly/openclaw-desktop:latest
```

This is different from `charly box inspect`, `charly box build`, and `charly check live` (the live-service runner), which key off `charly.yml` and accept short names unambiguously. Only the disposable-container runner has this restriction because it does not consult `charly.yml` at all.

## Three levels, three sections

| Section | Authored in | When it runs |
|---------|-------------|--------------|
| `candy` | `plan:` steps in the candy body, `candy/<name>/charly.yml` (build context) | `charly check box` + `charly check live` |
| `box` | `plan:` steps in the box body, `charly.yml` (build context) | `charly check box` + `charly check live` |
| `deploy` | a `plan:` step with `context: [deploy]`, or a local `charly.yml` overlay step | `charly check live <name>` only (deploy-context steps need a running deployment with port mappings, volumes, and resolved runtime variables) |

The `ai.opencharly.description` label carries the collected plan steps from all three
sections with `origin:` annotations (`candy:<name>`, `box:<name>`, `deploy-default`,
`deploy-local`). `CollectDescriptions` walks the base-image chain with a
visited-image guard: cycles are reported by `validateBoxDAG` at validate
time, but the collector itself terminates cleanly even if called on a
pathological config.

## Verb routing (which executor runs each check)

Every verb dispatches through one of two executors depending on the run
mode — this is what makes the same plan work both against a
disposable container (`charly check box`) and a running service (`charly check live`):

| Verb + attributes | Under `charly check live` (running service) | Under `charly check box` (disposable) |
|-------------------|-----------------------------------|------------------------------------|
| file, package, service, process, user, unix_group, interface, kernel-param, mount | `ContainerExecutor` (`podman exec`) | `ImageExecutor` (`podman run --rm`) |
| port with `listening` | `ContainerExecutor` (`ss`/`netstat` inside) | `ImageExecutor` |
| port with `reachable` | Host-side `net.DialTimeout` | Skipped (no host port binding on a disposable run) |
| command (`in_container: true`, default) | `ContainerExecutor` | `ImageExecutor` |
| command (`in_container: false`) | Host-side `exec.Command` | Skipped |
| http, dns, addr | Host-side (from the `charly` process) | In-container `curl` / `getent hosts` / `nc` |
| matching | In-process matcher check | Same |

The routing table lives in `charly/checkrun.go` (`runOne` switch) and
`charly/checkrun_verbs.go`. When a check is unroutable (e.g. `port:
reachable` under `charly check box`), the runner reports it as **skipped**
with a reason rather than failing the run.

### in-container `command:` stdin is guarded

An in-container `command:` script (`in_container: true`, the default) is
delivered to the pod shell over a stdin heredoc (`NestedExecutor.wrapWithJump`,
"stdin-attached exec"). The runner wraps every such script in
`{ <script>; } </dev/null` (`wrapContainerCommand`, `charly/checkrun.go`) so a
subcommand that reads stdin — `adb shell`, `ssh`, `read`, `cat` — cannot consume
the rest of the heredoc (the not-yet-run script lines, which would otherwise
truncate the check to its first command). Authors write plain multi-line
scripts; **no per-call-site `</dev/null` is needed**. Host-side `command:`
(`in_container: false`) runs via `sh -c` argv and is unaffected. For Android UI
readiness, prefer the typed `adb: wait-ui-settled` / `current-focus` / `keyevent`
verbs (`/charly-check:adb`) over shell entirely.

## Runtime variables

`charly check live` resolves these via `podman inspect` on the running container
before any check executes. `${NAME:arg}` is parameterized form.

| Variable | Source | Context |
|----------|--------|-------|
| `${USER}`, `${HOME}`, `${UID}`, `${GID}` | Image metadata (OCI labels) | build + deploy |
| `${IMAGE}` | Image metadata | build + deploy |
| `${DNS}`, `${ACME_EMAIL}` | Image metadata + charly.yml overlay | build + deploy |
| `${INSTANCE}` | `--instance` flag / charly.yml key | deploy |
| `${CONTAINER_NAME}`, `${CONTAINER_IP}` | `podman inspect` | deploy |
| `${HOST_PORT:N}` | Port mapping for container port N | deploy |
| `${VOLUME_PATH:name}` | Host path backing the named volume (bind source, encrypted mount, or `_data` dir) | deploy |
| `${VOLUME_CONTAINER_PATH:name}` | In-container mount path for a volume | deploy |
| `${ENV_NAME}` | Effective env var value on the running container | deploy |
| `${HOST:member}` | A SEPARATE member's container DNS name on the shared `charly` net (`charly-<member>`); no `:<port>` segment → container DNS; cross-member addressing (see below) | deploy |
| `${HOST:member:port}` | A host-reachable `127.0.0.1:NNNN` for a separate member's `port` (published port / VM ssh-forward); the `:<port>` segment selects host-vantage cross-member addressing | deploy |

Build-context steps may **not** reference deploy-context variables — the
validator flags this at `charly box validate` time.

**No bash-style defaults**: `${VAR:-fallback}` is unsupported (see
Authoring Gotcha #7). Plain `${VAR}` only.

## Cross-deployment probing — venue-from-position members + `${HOST:...}`

A check normally probes **the deployment under test**. Cross-deployment probing
lets ONE deployment act as a test DRIVER against a SEPARATE deployment as the
SUBJECT — the canonical case being a **Chrome DRIVER pod that CDP-probes a
separate web-server SUBJECT pod**, so a real browser tests the subject without
baking Chrome into the subject image. "A different kind of deployment tests
another kind" — pod→pod, local→pod, and local→VM, all through one mechanism.

Two pieces compose it:

- **venue-from-position members** — bring the driver up ALONGSIDE the subject on
  the shared `charly` network (see `/charly-core:deploy` "Sibling members"). A deploy
  declares each as a MEMBER NODE — a resource node on a substrate kind (`pod: {image: …}` / `vm: {from: …}` / `local: {from: …}`)
  placed directly under the deploy — and a plan step's EXECUTION VENUE is its TREE
  POSITION: a step in the `plan:` of member `M` runs ON `M` (bare name), a step in the
  `plan:` of a nested child `C` of parent path `P` runs on `P.C` (dotted). There is no authored
  `on:`/`pod:` step field — both are RETIRED; tree position is the sole source of
  venue (`flattenBundleVenues` stamps it at load time). A `cdp:`/`vnc:`/`mcp:` step
  placed under a driver member connects to that member's CDP/VNC/MCP endpoint; a
  `command:` step runs in that member's venue. Members are brought up by the same
  deploy verbs and are NEVER check-live'd (instruments, not subjects). A **GROUP**
  deploy (the `group:` kind) carries no workload of its own — it has no venue of its
  own, so every plan step MUST live under a member (a direct step on a group root is a
  hard load error). **Agent-provisioned members:** in an `iterate:` bed a member
  marked `agent_provisioned: true` is the artifact the AI BUILDS during the benchmark
  (e.g. the `os` venue), NOT something the bed brings up — `foldMembers` SKIPS it, so it
  is never a top-level addressable entry (no auto bring-up) and never collides cross-bed
  when the same venue name recurs across iterate beds; the scorer reaches its
  `charly-<name>` container via the bare-name fallback (`resolveScoringChain`).
- **`${HOST:...}` address variable** — lets the driven probe TARGET the subject;
  the presence of a `:<port>` segment selects which form resolves:
  - **`${HOST:<member>}`** (NO `:<port>`) → the member's container DNS name on the shared
    `charly` net (`charly-<member>`; also verifies it is running). The pod→pod address:
    `http://${HOST:<subject>}:8080`. Reference the subject by its OWN deploy
    name (for a bed, that's the bed name — the container is `charly-<bedname>`).
  - **`${HOST:<member>:<port>}`** (WITH `:<port>`) → a host-reachable `127.0.0.1:NNNN` for
    that member's `<port>` (container published port, or an ssh `-L` forward
    for a VM/host subject). The host-vantage address a `local`/host driver uses to
    reach a pod/VM subject. (Both are runtime-only — a build-context step can't use
    them.)

  An unresolvable `${HOST:...}` — the member/subject is unreachable (not running, bad
  port, VM ssh-forward refused) — **FAILS** the referencing check, never SKIPs it.
  A skip on an unreachable dependency is a fake pass: it would let a bed go green
  even though the cross-deployment probe never reached its target. (Legitimate
  skips — `skip: true`, `exclude_distro`, a deploy-only var under build context —
  are unaffected; only an unresolved mandatory `${HOST:...}` is treated as a failure.)

### Worked example — a Chrome pod CDP-probes a web-server pod (pod→pod)

```yaml
# charly.yml — a disposable GROUP deploy (no workload root): a web SUBJECT member +
# a chrome DRIVER member. Each is a resource node placed UNDER the deploy; each
# carries its own plan: list (venue = the member's name). Mirror
# box/fedora/charly.yml's check-cross-pod-cdp.
check-cross-pod-cdp:
    group:
        disposable: true             # group kind — no own workload (no image:/from:)
    web:                             # the SUBJECT member (nginx fixture on :8080)
        pod:
            image: web
            # No port: — every inherited container port auto-allocates a free
            # 127.0.0.1 host port (conflict-free across concurrent beds). Pin with
            # a port: entry (["H:C"]) only when a fixed host port is needed.
            plan:
                - check: the web subject serves its marker
                  id: web-fixture-up
                  context: [runtime]
                  http:
                      http: http://127.0.0.1:${HOST_PORT:8080}/
                      status: 200
                      body:
                          - contains: charly-fixture-web-content-marker
    chrome:                          # the DRIVER member (headless Chrome + cdp-proxy, publishes 9222)
        pod:
            image: chrome-headless
            plan:
                - check: chrome navigates to the subject over the charly net
                  id: cdp-open-web-subject        # venue=chrome (DRIVE; passes on exit 0)
                  context: [runtime]
                  cdp:
                      method: open
                      url: http://${HOST:web}:8080
                  eventually: 45s
                  retry_interval: 3s
                - check: the rendered page carries the marker
                  id: cdp-web-fixture-rendered    # also venue=chrome (ASSERT)
                  context: [runtime]
                  cdp:
                      method: text
                      tab: "1"       # the first page (cdp `open` lands on tab 1)
                  eventually: 30s
                  retry_interval: 3s
                  stdout:
                      - contains: charly-fixture-web-content-marker
```

`bringUpMembers` config+starts the chrome member alongside the web member; the
`cdp:` steps nested under `chrome` run with venue=chrome (dispatching the `cdp:`
verb out-of-process via `candy/plugin-cdp`, connecting to chrome's published 9222) while
`${HOST:web}` resolves to the web member's `charly-web` container, reached over the
shared net.

**Driver-box requirement (CDP):** a headless Chrome CDP driver MUST launch with
`--remote-allow-origins='*'` (Chrome 146+ rejects the CDP WebSocket upgrade
otherwise — `cdp open` via HTTP works, but `cdp text`/`check`/`screenshot` fail).
The `chrome-headless` box sets it; see `/charly-check:cdp` "Requirements".

### Cross-kind: a host driver reaching a pod OR a VM subject (`${HOST:<member>:<port>}`)

The `:<port>` (endpoint) form `${HOST:<member>:<port>}` is **kind-agnostic** — it routes through the ONE host-vantage
port resolver (`resolveCheckEndpoint`): a pod subject resolves to its auto-
published port (`podman port`); a VM subject resolves to an `ssh -L
127.0.0.1:<rand>:127.0.0.1:<guestport>` forward over the managed `charly-<vm>` alias
(the SAME forward `check-k3s-vm` uses to reach the cluster API host-side). So the
identical check — `command: curl …${HOST:<subject>:<port>}` placed under a
`kind: local` host-driver MEMBER (venue = that member) — proves a pod subject
(`check-cross-local-http`) and a VM subject (`check-cross-vm-http`) with ZERO
kind-specific check code; only the subject kind differs.

**The VM subject is driven from a host-side (`local:`) driver member, NOT a pod
driver.** `${HOST:<member>:<port>}` is a host-vantage `127.0.0.1:NNNN` address; a pod
driver can't reach it (that loopback is the pod's own netns), and a rootless
`qemu:///session` VM shares no L2 bridge with rootless pods. The generic, no-hack
VM cell therefore uses a local driver member — the host where both the published
port and the ssh-forward live. (`${HOST:<member>}` — no `:<port>`, pod-net container DNS — is the
pod→pod address and does NOT reach a VM.)

## charly.yml overlay rules

A local `charly.yml` can contribute its own `plan:` steps per deploy.
Merge rules applied by `charly check live`:

1. Local entries with an `id:` matching a baked entry replace that entry.
2. Entries without a matching `id:` are appended.
3. To disable a baked check, reference it with `id:` and `skip: true`.

```yaml
# ~/.config/charly/charly.yml — name-first: the redis-ml deploy with overlay plan: steps
redis-ml:
    pod:
        image: redis-ml
        plan:
            - check: redis answers ping             # overrides image's baked step (by id)
              id: redis-responds
              stdout: PONG
              command:
                  command: redis-cli -h 127.0.0.1 -p 16379 ping
                  in_container: false
            - check: the external tunnel is healthy # appended (no baked match)
              id: external-tunnel
              http:
                  http: https://redis.tailnet.ts.net/health
                  status: 200
            - check: a legacy baked step            # disable a legacy baked step
              id: old-probe
              skip: true
```

## Typical workflow

```bash
# 1. Author tests in candy/<name>/charly.yml.
# 2. Validate schema + references.
charly box validate

# 3. Build the image (the plan is auto-embedded as `LabelDescriptionSet`).
#    LABELs are emitted LAST in the final stage — a test edit rebuilds
#    in ~2 sec (cache hits every upstream RUN/COPY).
charly box build redis-ml

# 4. Run against a disposable container (build-context steps only).
charly check box redis-ml

# 5. Start the service and test end-to-end.
charly start redis-ml
charly check live redis-ml

# 6. Override a baked deploy check via local charly.yml, re-test.
$EDITOR ~/.config/charly/charly.yml    # add an overlay plan: step with matching id
charly check live redis-ml
```

## Coverage snapshot (7 currently-tested images)

Reference numbers from the last end-to-end session:

| Image | Tests | Pass | Fail | Skipped |
|-------|-------|------|------|---------|
| `filebrowser` | 24 | 24 | 0 | 0 |
| `jupyter` | 32 | 32 | 0 | 0 (includes 3 declarative `mcp:` checks) |
| `openwebui` | 24 | 24 | 0 | 0 |
| `hermes` | 50 | 50 | 0 | 0 |
| `immich-ml` | 63 | 61 | 0 | 2 (redis port internal) |
| `selkies-desktop` | 91 | 91 | 0 | 0 |
| `sway-browser-vnc` | 92 | 92 | 0 | 0 (includes 7 declarative cdp/wl/dbus/vnc/mcp checks; 2 mcp tests come from the chrome-devtools-mcp layer) |

**Total: 376 checks across 7 images (0 failing).**

The "skipped" entries are intentional — they reference ports that
aren't mapped in the containing image's `port:` block. Skipping them
is correct behavior; they'd pass in an image that does expose those
ports.

## Realistic run-time expectations

`charly check run default` is a multi-phase AI-iteration loop. Representative
per-phase durations (measured solving all 92/92 across 9 iterations on a
`disposable: true` check-sandbox):

| Phase | Plan segment | Typical iter1 duration | Notes |
|---|---|---|---|
| 1 | single-pod-system-state | ~10 min | trivial pod deploy |
| 2 | network-and-http | ~few min (cumulative scoring keeps phase 1 in scope) | nginx + curl in fedora:43 |
| 3 | cross-pod-nonce-traffic | ~few min | redis + redis-client; EVAL_NONCE_KEY/VALUE substituted per iter |
| 4 | mcp-protocol-probe | ~14 min | jupyter image build (~6 min) + 32 check steps |
| 5 | kubernetes-cluster | ~20-30 min | k3s/kwok cluster bring-up |
| 6 | desktop-display-and-input | ~50 min iter1, ~10 min iter2 | sway-browser-vnc image build (~14 min) + 13 cdp/wl/vnc checks; commonly takes 2 iters due to Chrome SIGBUS instability |
| 7 | vm-control-libvirt-spice | ~40-50 min | libvirt domain (cloud-init, qemu-guest-agent) + 9 checks |
| 8 | nested-deployment-chain | ~40 min | socket-passthrough nested pods + 9 cross-hop checks |

**Total wall-clock for a fresh `charly check run default`**: typically
**5-7 hours** on dev-class hardware. Set expectations accordingly — this
is NOT a quick smoke. For a fast canary that exercises the loader +
scoring paths end-to-end without real AI work, run
`charly check run scaffolding-selftest` (~5 min, a single-segment plan
that `include:`s `composition-import-selftest`).

The plateau bound is `iterate.plateau_iteration` (default 3). In
**progressive mode**, plateau ENDS the whole run — it does not advance
to the next phase, so an AI that stalls on one phase doesn't collect
easy wins on later phases it never engaged with.

## Issue 52328 (claude-code Bash + pgrep self-match deadlock) defense

The Claude Code runtime has a known issue documented in this project's
own `.check/ISSUE-claude-code-bash-pgrep-self-match-deadlock.md`: when
the AI uses `Bash{run_in_background: true}` with a `until ! pgrep -f
"<pattern>"` poll-loop, the literal pattern string is preserved in the
spawned bash's argv (because the wrapper uses `bash -c '… check
"<command>" …'`). `pgrep -f` then **matches itself**, the loop spins
forever, the parent `claude -p` process can't exit because it waits
for all background bash subprocesses, and the harness orchestrator
deadlocks waiting on claude.

The harness defends against this pattern between iterations: at every
iter end (in `check_loop.go`'s `commitIterationBestEffort`), the
orchestrator runs
`podman exec charly-check-sandbox pkill -f "while true.*sleep [0-9]+"` to
clean up orphaned keepalive bashes left dangling by the AI's
`TaskOutput`-timeout pattern, and logs the kill count.

Workaround for the AI inside the loop: prefer `kill -0 <PID>`-style
checks (track the original PID via `cmd & echo $!`) over `pgrep -f`
when the pattern would also match the wrapping bash. The harness
defense is a safety net, not a license to use the broken pattern
deliberately.

## Related skills

- **Live-container probe verbs — ALL out-of-process** — the `wl:` Wayland verb (`/charly-check:wl`), the `cdp:` Chrome-DevTools verb (`/charly-check:cdp`), the `vnc:` VNC-framebuffer verb (`/charly-check:vnc`), the `dbus:` D-Bus verb (`/charly-check:dbus`), the `mcp:` MCP-protocol verb (`/charly-build:charly-mcp-cmd`), the `record:` recording verb (`/charly-check:record`), the `kube:` cluster-probe verb (`/charly-kubernetes:check-k8s`), the `adb:` ADB verb (`/charly-check:adb`), the `appium:` Android-UI verb (`/charly-check:appium`), the `spice:` SPICE-wire verb (`/charly-check:spice`), and the `libvirt:` VM-probe verb (`/charly-check:libvirt`) are NOT host `charly check` subcommands — each is a declarative check verb served out-of-process by its plugin (`candy/plugin-wl`, `candy/plugin-cdp`, `candy/plugin-vnc`, `candy/plugin-dbus`, `candy/plugin-mcp`, `candy/plugin-record`, `candy/plugin-kube`, `candy/plugin-adb`, `candy/plugin-appium`, `candy/plugin-spice`, `candy/plugin-vm`). See the Live-container verbs section above.
- `/charly-image:layer` — layer authoring; the ordered `plan:` step list is part of every `charly.yml`.
- `/charly-image:image` — image-level plan steps at composition time.
- `/charly-core:deploy` — local `charly.yml` overlay rules and the plan-step merge.
- `/charly-build:validate` — static schema + cross-scope variable checks; the first
  gate before `charly box build`.
- `/charly-build:build` — how check entries are embedded into the OCI label at build
  time; LABELs-at-end cache behavior.
- `/charly-build:inspect` — view the merged plan / description structure as JSON.
- `/charly-build:migrate` — `charly migrate` brings legacy configs up to the
  current schema (one flat ordered `plan:` list per entity).
- `/charly-internals:go` — implementation map: `checkspec.go`, `checkvars.go`,
  `checkrun.go`, `checkrun_verbs.go`, `checkrun_charly_verbs.go`,
  `description_collect.go`, `check_cmd.go`, `check_runner_cmd.go`, `check_loop.go`,
  `check_runner_live.go`, `check_watchdog.go`, `validate_check.go`,
  `mcp.go`, `mcp_client.go`, plus the `LabelDescriptionSet` type in `labels.go`.
- `/charly-internals:generate-source` — how `LabelDescriptionSet` is written into the Containerfile
  via `writeJSONLabel`, and why the LABEL block lives at the end of the
  final stage.
- `/charly-internals:capabilities` — the `ai.opencharly.description` label (`LabelDescriptionSet`) carrying the baked plan is
  part of the same capability contract as `LabelService`.
- `/charly-internals:agents` — the sub-agents (`check-bed-runner`,
  `deploy-verifier`) and dynamic workflows (`/verify-beds`,
  `/audit-deploy-configs`) that DRIVE these beds, and the R10/disposable/
  paste-proof rules that bind any agent or workflow running `charly check run`.
- `/charly-internals:plugin` — a `check:` step's `<word>: <input>` verb sugar dispatches
  to a plugin-provided verb (built-in or out-of-tree); the desugared internal input is
  validated at runtime against the plugin's served CUE schema before `runPluginVerb`
  invokes it.

## When to Use This Skill

**MUST be invoked** before authoring, running, or debugging check
behavior at any level. Triggers: `charly check` (any subcommand), `charly check
run`, `charly check box`, `charly check live`, the plan steps / `description:`
field in a candy/box `charly.yml`, the disposable test-bed deploys, the
`ai.opencharly.description` OCI label, `kind: agent` (the agent grader) or a
`disposable: true` deploy (+ its `iterate:` block),
`charly check run <bed>` (disposable R10 deploys; roster fan-out via `/verify-beds`), or any check
verb by name (file/port/http/command/package/service/cdp/wl/dbus/vnc/mcp/...).
