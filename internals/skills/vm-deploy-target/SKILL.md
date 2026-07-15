---
name: vm-deploy-target
description: |
  The external VM deploy substrate applies InstallPlan inside a guest through
  the reverse-channel SSH executor. Use for plugin-deploy-vm, VM boot and guest
  readiness, Charly delivery, nested pods, lifecycle preparation and teardown,
  VmDeployState persistence, grpcSubstrateLifecycle, DeployExecutor, or the
  generic externalDeployTarget and UnifiedDeployTarget seams.
  SSHExecutor, VmDeployState persistence, and the host-side ledger.
  Source: candy/plugin-deploy-vm/lifecycle.go, charly/vm_lifecycle_preresolve.go,
  charly/substrate_lifecycle_grpc.go, charly/deploy_substrate_lifecycle.go,
  charly/deploy_target_external.go, sdk/kit/deploy_executor*.go,
  charly/bundle_add_cmd_vm.go.
  MUST be invoked before editing VM-target deploy code.
---

# vm-deploy-target

## The `vm` substrate is external (out-of-process)

`vm` is one of the EXTERNAL deploy substrates (`externalizedDeploySubstrates`
in `charly/provider_deploy.go`, alongside `local`/`android`/`k8s`). There is
no in-proc VM deploy target: the plan WALK runs OUT-OF-PROCESS in
`candy/plugin-deploy-vm` (serving the `deploy:vm` word) — a near-clone of
`candy/plugin-deploy-local`. The plugin receives the deployment's `InstallPlan`
VIEWS over the executor reverse channel and walks them via the shared
`sdk/kit.WalkPlans` — the SAME walk `deploy:local` uses. The
difference is purely the executor's TRANSPORT: the executor the reverse channel
serves for a vm deploy is the **guest `SSHExecutor`**, so the SAME `kit.WalkPlans`
that runs a local deploy on the host runs a vm deploy **inside the guest** over SSH.

Step routing inside the walk (`kit.WalkPlans`):

- **Plugin-renderable steps** — `Op` (write/cmd/download), `File`, `ShellHook`
  (+ the env.d managed-block finalizer `ensureVenueManagedBlock`),
  `ShellSnippet`, `ServicePackaged`, `ServiceCustom`, `RepoChange` — the plugin
  executes ITSELF via the F2 reverse legs (`RunSystem` / `RunUser` / `PutFile` /
  `GetFile`), ECHOING the host-computed `view.ReverseOps`.
- **Host-engine steps** — `Builder` / `LocalPkgInstall` / `SystemPackages` /
  act-verb `Op` / `ExternalPlugin` — the plugin drives over `RunHostStep`
  (host-side: builders run on the host's podman, artifacts scp into the guest).
- **`RebootStep`** (a `reboot: true` kernel-module layer) — also driven over
  `RunHostStep`, where the HOST reboots the guest and waits for the
  deterministic boot_id change.

Because `{{.Home}}` is resolved against the GUEST home host-side (the served
executor's `ResolveHome` targets the guest), the plugin ships no substrate
payload. It returns a `DeployReply` carrying the combined teardown ops the host
records in the install ledger and replays at `charly bundle del`
(record-and-replay).

## `externalDeployTarget` — the generic adapter

`externalDeployTarget` (`charly/deploy_target_external.go`) is the generic
out-of-process adapter. In-proc, two targets implement the bare
`DeployTarget` (Name + Emit) interface — `OCITarget` (pod-overlay `add_candy:`
Containerfile synthesis; `charly box build`/`generate` itself uses the separate
`WriteCandySteps` → `EmitTasks` generator in `sdk/deploykit`, relocated in #67) and `PodDeployTarget` (the pod
overlay-BUILD engine) — but both are now BUILD ENGINES invoked HOST-SIDE from a
lifecycle hook (`candy/plugin-deploy-pod`'s PrepareVenue (M4)), NOT deploy targets
dispatched by `ResolveTarget`. The deploy LIFECYCLE is the separate
`UnifiedDeployTarget` interface (Add/Del/Test/Update/Start/…/Rebuild), and its
sole implementer is the generic `externalDeployTarget`. **ALL FIVE external
substrates (`local`/`vm`/`pod`/`k8s`/`android`) route through
`externalDeployTarget`** over the executor reverse channel, each served by its
own out-of-process plugin.
`externalDeployTarget.Add` Invokes the
provider (`OpExecute`) with the deployment's `InstallPlan` views in `op.Params`
and a venue descriptor in `op.Env`, serving the host's executor on the go-plugin
broker so the plugin runs the deployment's shell/SSH ops on the real venue;
`Del` replays the RECORDED `ReverseOps` from the ledger (no plugin call). See
`/charly-internals:install-plan` for the shared IR.

## The vm venue lifecycle — implemented in the plugin over generic seams

Unlike `local`/`android`/`k8s` (whose venue has no charly-owned lifecycle beyond
the walk), `vm` owns a real venue lifecycle: charly boots / destroys / consoles /
SSHes the domain, and `charly update <vm-bed>` MUST
destroy+build+create+start+re-add the domain (the R10 fresh-rebuild gate). That
lifecycle is IMPLEMENTED IN THE PLUGIN — NOT in core, and NOT a hollow forward:

- `candy/plugin-deploy-vm` declares `Lifecycle: true`, so at plugin-load the
  generic `grpcSubstrateLifecycle` proxy (`charly/substrate_lifecycle_grpc.go`)
  is registered for the `deploy:vm` word. The proxy Invokes the plugin's
  lifecycle Ops (`OpPrepareVenue` / `OpPostApply` / `OpStart` / `OpStop` /
  `OpStatus` / `OpLogs` / `OpShell` / `OpRebuild` / `OpTeardownExecutor` /
  `OpArtifactKey` / `OpPostTeardown`), consulting the registry GENERICALLY —
  it never branches on `"vm"` directly.
- The plugin (`candy/plugin-deploy-vm/lifecycle.go`) implements each Op ITSELF
  over three GENERIC seams:
  - **sdk/kit** — the ssh-config stanza (`kit.WriteVmSshStanza` +
    `kit.EnsureSshConfigInclude`), the guest-readiness waits (`kit.WaitForSSH` /
    `kit.WaitForCloudInit` / `kit.WaitForPackageLock`, host-surface ssh with an
    injected poll), and charly delivery (`kit.EnsureCharlyInGuest` /
    `kit.EnsureCharlyInVenue`).
  - **`HostBuild("cli")`** — the generic "cli" host-builder that runs
    `charly vm build/create/start/stop/console/ssh/destroy` and
    `charly box build` / `charly vm cp-box` on the host (auto-boot,
    start/stop/logs/shell/rebuild, nested-pod image build).
  - **the reverse channel** — the served guest `SSHExecutor` the plugin drives
    for the in-guest nested-pod `from-box` deploy (`OpPostApply`).

Core provides ONLY generic seams + host-resolved DATA the plugin cannot compute
(it has no project):

- A **`lifecyclePrepareHook`** registry (`charly/vm_lifecycle_preresolve.go`):
  the vm hook (`vmLifecyclePrepare`) does `LoadUnified` → `spec.Vm`, resolves the
  `kind:vm` entity (`vmEntityForAdd`) + the ssh user/port + the prior
  `VmDeployState`, and ships `spec.LifecyclePrepareInput` on the `OpPrepareVenue`
  params — the SAME data-seam shape as the in-core k8s/android
  `deployPreresolvers`. The proxy consults it GENERICALLY by substrate word
  (`lifecyclePrepareHookFor`); pod registers none.
- A **`lifecyclePostTeardownHook`** (same file): the one residual host cleanup
  the plugin can't do — vm's ephemeral-lifecycle teardown (systemd timers +
  libvirt snapshot refcounts).
- The proxy persists the plugin's returned `VmDeployState` patch via the generic
  `saveDeployState` (extended with `VmState` / `VmCrossRef`), and removes the
  charly.yml entry keys the plugin ships in `PostTeardownReply.RemoveEntries`.

So NO vm lifecycle logic remains in core: the plugin owns the venue lifecycle
over the generic seams, and core owns only the DATA preresolver + the ephemeral
post-teardown hook + generic state persistence. This is the vm analog of pod
(`candy/plugin-deploy-pod`, which drives `HostBuild("overlay")` +
`HostBuild("cli")`).

Each Op:

| Op | What it does |
|---|---|
| `OpPrepareVenue` | The full venue preflight, run BEFORE the walk. Consumes the host `lifecyclePrepareHook`'s resolved `spec.LifecyclePrepareInput`; writes the managed ssh-config Host stanza (`kit.WriteVmSshStanza` + `kit.EnsureSshConfigInclude`), auto-boots the domain via `HostBuild("cli")`, waits (`kit.WaitForSSH` / `WaitForCloudInit` / `WaitForPackageLock`), `kit.EnsureCharlyInGuest`, then returns the guest-`SSHExecutor` `VenueDescriptor` the proxy re-materializes + serves and the `VmDeployState` patch the proxy persists. |
| `OpArtifactKey` | Keys candy artifacts (+ the k3s `ClusterProfile`) under `vm:<entity>`, NOT the deploy name — one k3s cluster per VM is reached by several beds, so its profile lands under the shared `vm-<entity>` name the `cluster:` refs use. |
| `OpPostApply` | Deploys nested `target: pod` children as persistent in-guest quadlets over the served guest executor, AFTER the walk (so the VM's own candies + any kernel-driver reboot are already applied). Add only; skipped under `--node-only`. |
| `OpTeardownExecutor` | Returns the guest-`SSHExecutor` `VenueDescriptor` (against the managed alias, no boot) the recorded `ReverseOps` replay over IN THE GUEST. |
| `OpPostTeardown` | Removes the managed ssh-config stanza (`kit.RemoveVmSshStanza`) and ships the charly.yml entry keys to strip in `PostTeardownReply.RemoveEntries`; the core `lifecyclePostTeardownHook` runs the residual ephemeral-lifecycle teardown. |
| `OpStart` / `OpStop` / `OpStatus` / `OpLogs` / `OpShell` / `OpRebuild` | Drive the `charly vm` family via `HostBuild("cli")`. `OpRebuild` does `charly vm destroy` + `build` + `create` + `start` + `charly bundle add <name>` (re-applying the deploy's candies to the fresh guest via the shared layer-apply primitive, R3) — the path `charly update <vm-bed>` routes through. |

## Implementation notes

- The `pod` substrate is EXTERNAL (`deploy:pod`, candy/plugin-deploy-pod); `PodDeployTarget` (`charly/deploy_target_pod.go`) is its RETAINED overlay-BUILD engine, invoked HOST-SIDE from `candy/plugin-deploy-pod`'s PrepareVenue (M4) (`charly/build_overlay.go`). Its teardown record is keyed HOST-SIDE by `computeDeployID(name)` like every external deploy (the in-proc pod was record-free).
- `vmNameFromDeployName` strips the `vm:` prefix. `vmEntityForAdd` (`charly/vm_lifecycle_preresolve.go`, used by the host prepare hook) resolves the `kind:vm` entity from a deploy node: the node's `vm:` cross-ref (`node.From`) wins, then the persisted cross-ref, then a legacy `vm:<entity>` prefix, then the deploy name itself.
- `UnifiedDeployTarget` / `LifecycleTarget` interfaces (`charly/deploy_target_unified.go`) + the `ResolveTarget` dispatcher (`charly/unified_targets.go`) provide the full lifecycle contract (`Add` / `Del` / `Test` / `Update` / `Start` / `Stop` / `Status` / `Logs` / `Shell` / `Rebuild`). `ResolveTarget` returns an `externalDeployTarget` for every externalized substrate (local/vm/pod/k8s/android — all five).
- Disposability is read per-`BundleNode` via `charly/deploy.go::BundleNode.IsDisposable()` (`disposable: true`, or ephemeral); it is NOT a `VmSpec` field. The disposability-as-authorization gate is NOT applied in the `charly update` path — `charly update <vm>` rebuilds on explicit invocation regardless (it only NOTES non-disposability, never refuses). `externalDeployTarget.Rebuild` delegates through the `grpcSubstrateLifecycle` proxy to the plugin's `OpRebuild` (over `HostBuild("cli")`), which recreates the domain THEN re-applies the deploy node's layers via the shared `charly bundle add <node>` path — the same layer-apply primitive the local/pod Rebuild use (R3).

The `vm` substrate brings `charly bundle add vm:<name>` online: the same
`InstallPlan` IR that drives pod builds and host deploys runs **inside a VM**
over SSH. Shell bodies that a `local:` deploy would exec via local `sudo bash -s`
are instead exec'd via `ssh guest 'sudo bash -s'` through the guest
`SSHExecutor`. The teardown ledger is keyed HOST-SIDE by
`computeDeployID(deployName)` (like every external deploy); teardown replays the
recorded `ReverseOps` over the guest SSH executor (an `sshReverseRunner` derived
from the executor), so the reverse ops run IN THE GUEST.

## Source files

| File | Contents |
|---|---|
| `charly/deploy_target_external.go` | `externalDeployTarget` — the generic out-of-process adapter for all five external substrates; `Add` Invokes `deploy:vm` over the reverse channel, `Del` replays recorded `ReverseOps` |
| `charly/deploy_substrate_lifecycle.go` | the generic `substrateLifecycle` interface + the `substrateLifecycleFor` registry (wire-backed hooks register via `registerPluginSubstrateLifecycle` at plugin-load) |
| `charly/substrate_lifecycle_grpc.go` | `grpcSubstrateLifecycle` — the generic proxy implementing `substrateLifecycle` by Invoking an out-of-process substrate's lifecycle Ops; consults the `lifecyclePrepareHook` / `lifecyclePostTeardownHook` by word, re-materializes the plugin's returned `VenueDescriptor`, and persists the returned `VmDeployState` via `saveDeployState` |
| `charly/vm_lifecycle_preresolve.go` | the vm `lifecyclePrepareHook` (`vmLifecyclePrepare` — `LoadUnified` → `spec.Vm` + entity + ssh user/port + prior `VmDeployState`, shipped as `spec.LifecyclePrepareInput`) + the vm `lifecyclePostTeardownHook` (ephemeral-lifecycle host cleanup); `vmEntityForAdd` |
| `candy/plugin-deploy-vm/lifecycle.go` | the plugin's venue lifecycle — implements every lifecycle Op (`OpPrepareVenue` / `OpPostApply` / `OpStart` / … / `OpPostTeardown`) over `kit` + `HostBuild("cli")` + the served guest executor |
| `candy/plugin-deploy-vm/` | the out-of-process `deploy:vm` plugin (the plan WALK via `kit.WalkPlans` over the guest `SSHExecutor`) |
| `sdk/kit/deploy_executor.go` | `DeployExecutor` interface (RunShell, Scp, Close) + `ShellExecutor` — local shell exec (used host-side for the builder-image step and `RunHostStep`) |
| `sdk/kit/deploy_executor_ssh.go` | `SSHExecutor` — ssh client with passt-friendly timeouts + WaitForSSH + WaitForCloudInit |
| `charly/bundle_add_cmd_vm.go` | VM-only host-side deploy helpers that REMAIN: `vmNameFromDeployName`, `sshReverseRunner`, `resolveVmSshUser` / `resolveVmSshPort`, `saveVmDeployState`, `removeVmDeployEntry` |
| `candy/plugin-vm/vm_create_orchestrate.go` | `VmCreateCmd.runVmSpecCreate` — prereq: VM must be created before deploy (the `command:vm` plugin; the backend-specific `runVmSpecCreateLibvirt`/`-Qemu` are in `vm_create_spec.go`) |

## DeployExecutor interface

```go
type DeployExecutor interface {
    RunShell(ctx context.Context, script string, opts ShellOpts) (ExecResult, error)
    Scp(ctx context.Context, src io.Reader, dst string, mode os.FileMode) error
    Close() error
}
```

Two implementations:

- `ShellExecutor` — `bash -c <script>` / file copy. Used host-side for container-builder invocations (the `RunHostStep` leg) and by the dry-run path of any target.
- `SSHExecutor` — ssh/scp via `golang.org/x/crypto/ssh`. Used for the `vm` substrate (the guest executor the reverse channel serves) and for a `local: {host: user@machine}` remote. Carries Host/Port/User/KeyPath + maintains a persistent connection across multiple shell invocations.

**Name choice**: the interface is `DeployExecutor` — a deploy-scoped name kept distinct from the check runner's own execution types.

## OpPrepareVenue preflight flow

The venue preflight runs in TWO parts. FIRST the host `lifecyclePrepareHook`
(`vmLifecyclePrepare`, `charly/vm_lifecycle_preresolve.go`) resolves the DATA the
plugin can't compute — it `LoadUnified`s the project, resolves the `kind:vm`
entity (`vmEntityForAdd`) + its `VmSpec`, the ssh user/port (`resolveVmSshUser` /
`resolveVmSshPort`), and the prior `VmDeployState`, and ships them as
`spec.LifecyclePrepareInput` on the `OpPrepareVenue` params. The `Alias`,
`StateDir`, and `SSHPort` in that input key off the per-deploy DOMAIN IDENTITY
(`charly-<VmDomainIdentity(deploy)>`, not the shared `kind:vm` entity), so sibling
beds on one entity get distinct domains + state dirs + auto-allocated ports (P33);
`Entity` still names the disk/spec source. THEN the plugin's
`OpPrepareVenue` (`candy/plugin-deploy-vm/lifecycle.go`) runs the venue steps
over the generic seams, BEFORE the walk:

1. **Publish the managed ssh-config stanza** (`kit.WriteVmSshStanza`) for the VM alias + `kit.EnsureSshConfigInclude`.
2. **Auto-boot** via `HostBuild("cli")`: TCP-probe the SSH port and, if unreachable, `charly vm build` + `charly vm create`. No-op in DryRun, when nested, and when `CHARLY_DEPLOY_NO_AUTOBOOT` is set.
3. **Wait for SSH.** `kit.WaitForSSH` — polls `net.Dial` to `host:port` with exponential backoff (an injected poll), accommodating cold-boot VMs where cloud-init is provisioning sshd.
4. **Wait for cloud-init + package lock** (cloud_image / cloud-init sources). `kit.WaitForCloudInit` polls `cloud-init status --wait`; `kit.WaitForPackageLock` waits for the package manager.
5. **`kit.EnsureCharlyInGuest`.** Runs the `VmCharlyInstall.Strategy` state machine (see `/charly-internals:cloud-init-renderer`).
6. **Return the guest `SSHExecutor` `VenueDescriptor`** (the proxy re-materializes it + the reverse channel serves it to the walk) and the **`VmDeployState` patch** the proxy persists via `saveDeployState`.

The plugin's `kit.WalkPlans` then resolves the guest home (`exec.ResolveHome`),
walks the plans inside the guest, and writes the guest ledger / env.d via the
reverse legs.

## Guest-home resolution (deploy-time `{{.Home}}`)

Home-bearing step fields — `ShellHookStep` env values + `path_append`,
`ShellSnippetStep` snippet/destination, `FileStep.Dest` — are compiled with the
deferred `{{.Home}}` token (`HomeToken`), NOT a baked compile-time home. For an
external deploy, `externalDeployTarget.prepareReverseState` resolves the token
host-side against the VENUE home (`t.exec.ResolveHome`) before projecting the
views — for `vm` the **GUEST** home, because the served executor is the guest
`SSHExecutor`. This is why a `target: vm` deploy writes
`/home/<guest-user>/.config/opencharly/env.d/<layer>.env` whose contents point
at `/home/<guest-user>/…` rather than the host operator's home. `cmd:` task
bodies are left untouched — `~`/`$HOME` there shell-expand at runtime on the
guest as the deploy user, already correct. See `/charly-internals:install-plan`
"Deferred home resolution".

## env.d-sourcing managed block (guest login shell)

The env.d-sourcing managed block is written by `kit.WalkPlans`'s finalizer
(`ensureVenueManagedBlock`) over the served (guest) executor — so for a `vm`
deploy it lands in the guest's detected login-shell init via the reverse legs
(`GetFile` the existing rc, merge the fenced block, `PutFile` it back). The
shared body/path helpers (`ManagedBlockBody`, `ShellInitFilePath`)
live in `charly/shell_profile.go`; the block-splice itself is kit's (`sdk/kit/profile.go`); the plugin renders the equivalent via
`sdk/kit/profile.go`. Without this block the per-layer env.d files
exist but are never sourced, so PATH never picks up `~/.npm-global/bin` etc. The
shell is detected from the GUEST `/etc/passwd` (getent), because the guest's
interactive default may differ from the operator's (CachyOS ships fish) —
writing bash syntax to `~/.profile` when the guest runs fish would never load.

## Cross-host builders (npm / pixi / cargo / aur)

Builders run on the HOST (podman) and ship the result into the guest — guests
never need a container runtime. For a `vm` deploy the plugin drives the
`Builder` / `LocalPkgInstall` step over `RunHostStep`, so the host builds and
the artifact streams in:

- **aur** → builds `.pkg.tar.zst` in a host staging dir, scp's them in, `pacman -U`.
- **npm / pixi / cargo** → bind-mounts a host staging dir AS the **guest home path**
  so npm shebangs / cargo rpaths / pixi activation scripts bake the path the guest
  will actually use, then tars the produced home subdirs (`~/.npm-global`, `~/.pixi`,
  `~/.cargo`; caches excluded), scp's the tarball in, and extracts it into the guest
  `$HOME` **as the guest user** so ownership + baked paths are correct. The builder
  image resolves via `resolveBuilderImage`. Unknown builders honor `--skip-incompatible`.

This is what makes the full charly-cachyos stack — including the npm-builder AI CLIs
(`claude-code`, `codex`, `gemini`, `oracle`, `forgecode`) — install on a VM.

## RebootStep — only the vm deploy reboots

When a layer declares `reboot: true`, `BuildDeployPlan` appends a trailing
`RebootStep`. Only the external `vm` deploy acts on it: the plugin drives it
over `RunHostStep`, where the HOST reboots the guest (records the guest's
`/proc/sys/kernel/random/boot_id`, fires `(sleep 1; systemctl reboot) &` so the
ssh session closes cleanly, then polls until SSH answers AND the boot_id has
changed — deterministic, not a fixed sleep, so the still-up pre-reboot sshd
can't be mistaken for "back up"). OCI/pod/k8s skip it; the external `local:`
deploy skips + warns — it never reboots the operator host. This is what lets a
kernel-module layer (e.g. the CachyOS `nvidia-driver` layer) load its module on
a clean boot mid-deploy. See `/charly-internals:install-plan` RebootStep.

## Host→guest image transfer (`charly vm cp-box`)

`charly vm cp-box <vm> <ref> [--as <tag>] [--rootless]` (and the reusable
`TransferImageToGuest` helper) stream a host-built image into a running guest's
podman storage via `podman save | ssh podman load` (NO intermediate tarball —
the guest `/tmp` tmpfs is too small for a multi-GB image), idempotent (skips an
intact present image, re-streams a torn-overlay one — a name-only check would
wrongly skip a corrupt image) and offline (no registry). `--rootless` selects the
storage, and ALL of the load / integrity-probe / tag steps follow it consistently
(via the `podmanCmd(rootless)` helper):

- **default** → the guest's ROOT podman (`sudo podman`), for a `sudo podman run
  --device nvidia.com/gpu=all` consumer that needs `/dev/nvidia*` via root.
- **`--rootless`** → the SSH user's ROOTLESS podman (`podman`, no sudo; the tag
  runs via `RunUser`, not `RunSystem`). This is what the plugin's `OpPostApply`
  nested-pod deploy uses: the nested pod comes up via the guest user's own `charly bundle from-box`
  (a `--user` quadlet) which reads the USER's storage, so the image MUST land
  there — a root-loaded image would be invisible to it.

## Nested pod-in-VM — persistent in-guest quadlet (the plugin's `OpPostApply`)

A `target: vm` deploy whose `nested:` map has `target: pod` children brings each
child up as a PERSISTENT in-guest quadlet — the nested-pod-in-VM capability.
The plugin's `OpPostApply` (`candy/plugin-deploy-vm`) brings up each nested pod AFTER the plan
walk (so the guest's own layers, including any kernel-driver reboot + the
boot-time `nvidia-ctk cdi generate`, are already applied). For each child it:

1. `charly box build <child.Image>` on the HOST (the guest needs no project).
2. `charly vm cp-box <vm> <child.Image> --as localhost/charly-<childKey>:latest
   --rootless` — into the guest USER's rootless podman.
3. over SSH as the guest user: `loginctl enable-linger` (so the `--user` quadlet
   auto-starts at boot and survives reboot), then `export
   XDG_RUNTIME_DIR=/run/user/$(id -u)` (so `systemctl --user` reaches the
   lingering user bus over the non-login SSH session), then the guest's own
   project-free `charly bundle from-box localhost/charly-<childKey>:latest
   <childKey>` — which generates + starts the quadlet from the image's baked OCI
   labels (ports, services, GPU device auto-detected in the guest; rootless GPU
   via CDI — `/dev/nvidia*` are world-rw and the CDI spec is world-readable).

Idempotent (cp-box skips an intact image; from-box re-applies on `charly update`).
The dispatch routes a VM-root deploy node-only (its pod children deploy in-guest
here, never via a host tree walk). `charly check live <vm>.<pod>` evaluates the
running nested pod by DELEGATING to the guest `charly check live <pod>` (where it is
a direct pod — guest-local podman + ports + the guest `charly`), so the protocol
verbs (cdp/wl/dbus/vnc/mcp) and `${HOST_PORT}` checks run natively instead of
skipping; see `/charly-check:check` "parent.child reaches the actual leaf". `charly vm
cp-box` is the host→guest image delivery for it.

## VmDeployState persistence

```go
type VmDeployState struct {
    InstanceID              string                  // stable UUIDv4 cloud-init instance-id, pinned across re-renders
    DiskPath                string                  // absolute path to the qcow2 (may be a CoW overlay on a cached base)
    SeedIso                 string                  // NoCloud cidata ISO path (empty for bootc with injection disabled)
    SshPort                 int                     // host port forwarded to the guest's :22
    SshUser                 string                  // guest account the deploy SSHes in as
    Backend                 string                  // "qemu" or "libvirt", pinned at first apply
    KeyInjectionResolved    *VmKeyInjectionResolved // resolved SSH key-injection plan
    CharlyInstallStrategy       string                  // how charly is installed into the guest
    CloudInitRenderedDigest string                  // digest of the rendered cloud-init (re-render detection)
    Snapshots               []VmSnapshotState       // libvirt snapshot ledger
    Ephemeral               *EphemeralRuntime       // transient run-state for an ephemeral VM
}
```

Persisted in `~/.config/charly/charly.yml` as the `vm_state:` field on the VM's deploy entry (`BundleNode.VmState`). On a deploy the plugin returns the `VmDeployState` patch from `OpPrepareVenue`, and the `grpcSubstrateLifecycle` proxy persists it via the generic `saveDeployState` (extended with `VmState` / `VmCrossRef`). Each `charly vm build` / `charly vm create` / `charly bundle add vm:<name>` iteration updates the relevant fields. `charly bundle del vm:<name>` preserves the state (so re-adding picks up InstanceID etc.) unless `--purge` is passed.

## SSH key idempotency

`generateSSHKeypair` in `charly/vm_backend_lifecycle.go` (the core-retained seam) checks for `<vmStateDir>/id_ed25519.pub` before creating. Rebuilding a VM doesn't regenerate the keypair. First `charly vm build` writes the keypair; subsequent calls leave it untouched — so iterated rebuilds keep a stable pubkey and SSH stays valid.

## CLI dispatch: bundle add → ResolveTarget → externalDeployTarget

`charly bundle add vm:<name>` resolves via `bundle_add_cmd.go::dispatchNode` →
`ResolveTarget` → `externalDeployTarget` when the deploy node is a `vm:`
substrate (or the deploy name starts with `vm:`). `externalDeployTarget.Add`
runs the venue preflight through the `grpcSubstrateLifecycle` proxy — the host
`lifecyclePrepareHook` resolves the DATA, then the plugin's `OpPrepareVenue`
boots the domain + returns the guest executor — then Invokes `deploy:vm` to walk
the plans inside the guest:

```
charly bundle add vm:arch ripgrep           # apply ripgrep layer in the guest
charly bundle add vm:arch fedora-coder \    # apply full fedora-coder layer set
    --add-candy team-extras \
    --add-candy github.com/team/configs/candy/sshkeys
charly bundle del vm:arch                   # reverse all applied layers in the guest
```

Prereq: the VM is auto-booted by the plugin's `OpPrepareVenue` if not already reachable
(`charly vm build` + `charly vm create`), or you can create it explicitly first
(`charly vm create arch`).

## passt backend + SSH port forwarding

When the VM's network uses libvirt user-mode + `<backend type='passt'/>` + `<portForward>` (see `/charly-internals:libvirt-renderer`), the guest `SSHExecutor` connects to `127.0.0.1:<host-port>`. The portForward maps that through passt into the guest's `:22`. The indirection is invisible to `SSHExecutor` — it sees a normal TCP connect.

## Cross-References

- `/charly-internals:install-plan` — InstallPlan IR (the in-proc DeployTarget implementers + step kinds; `externalDeployTarget` consumes the IR for the external substrates)
- `/charly-internals:plugin` — the out-of-process plugin model + the executor reverse channel `candy/plugin-deploy-vm` rides
- `/charly-internals:vm-spec` — VmSpec consumed by the vm deploy plugin's host prepare hook
- `/charly-internals:libvirt-renderer` — renders domain XML; portForward + passt backend
- `/charly-internals:cloud-init-renderer` — `kit.EnsureCharlyInGuest` (runs in the plugin's `OpPrepareVenue`)
- `/charly-core:deploy` — `charly bundle add vm:<name>` command + charly.yml schema
- `/charly-local:local-deploy` — the sibling external substrate (`deploy:local` via `candy/plugin-deploy-local`); same `kit.WalkPlans` + ReverseOps model
- `/charly-vm:vm` — VM lifecycle; creates the venue the vm deploy runs against
- `/charly-vm:arch-cloud-vm` — canonical worked example — VmDeployState persistence; ssh_key idempotency live-test
