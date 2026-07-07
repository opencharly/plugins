---
name: local-infra
description: |
  Go file map for the host side of the `local:` (external deploy:local plugin) +
  VM deploy execution surface. Files: local_spec.go, deploy_chain.go,
  sdk/kit/sshconfig.go, sdk/vmshared/hostdistro.go, install_ledger.go, builder_run.go,
  shell_profile.go, reverse_ops.go, service_render.go, deploy_ref.go.
  MUST be invoked before reading or modifying any of those files, or when
  debugging `local:` / VM deploy behaviour (ledger state, sudo batching,
  managed-block insertion, glibc preflight, ssh-config fragment, ref resolution).
---

# Local Infra — Go files that support target:local deployments

## Overview

The `InstallPlan` IR (see `/charly-internals:install-plan`) is the central data type. The `local:` and `vm:` substrates are BOTH served OUT-OF-PROCESS by external plugins (`deploy:local` via `candy/plugin-deploy-local`, `deploy:vm` via `candy/plugin-deploy-vm`): `externalDeployTarget` hands each the IR over the executor reverse channel and the plugin walks it via the SAME `sdk/kit.WalkPlans` (the vm one over the guest `SSHExecutor`, so the walk runs inside the guest). These HOST-side supporting files back those external walks for each concrete concern: distro detection, ledger I/O, builder-container invocation, ReverseOp execution (teardown), service rendering, ref resolution, the host-executor pick (`rootExecutorForDeployNode`), and the managed ssh-config fragment that VMs publish on create. The host-engine step kinds the plugin cannot render itself (Builder / LocalPkgInstall / SystemPackages / act-verb Op / ExternalPlugin) run on the host via the `RunHostStep` reverse-channel RPC; the plugin renders the remaining shell/file/service steps itself via the kit equivalents (`sdk/kit/profile.go`, `render.go`).

## File map

| File | Purpose | Key exports |
|---|---|---|
| `charly/local_spec.go` | `LocalSpec` struct + `findLocalSpec` lookup | `LocalSpec`, `findLocalSpec` |
| `charly/deploy_chain.go` | `rootExecutorForDeployNode` — picks the root `DeployExecutor` for a `local:` deploy node (`ShellExecutor` for `host:local`/absent, `SSHExecutor` for `host:<user@machine>`) | `rootExecutorForDeployNode` |
| `charly/deploy_target_external.go` | `externalDeployTarget` — Add/Test/Update/Del lifecycle for the externalized `local:` substrate (and k8s/android) over the executor reverse channel; records/replays teardown ops via the ledger (full detail in `/charly-internals:install-plan`) | `externalDeployTarget` |
| `sdk/kit/sshconfig.go` | `~/.config/charly/ssh_config` fragment writer (managed-block protocol) | `kit.WriteVmSshStanza`, `kit.RemoveVmSshStanza`, `kit.ListVmSshAliases`, `kit.EnsureSshConfigInclude`, `kit.RemoveSshConfigInclude`, `kit.VmSshAlias`, `kit.SshFragmentPath`, `kit.SshConfigPath` |
| `charly/deploy_executor_ssh.go` | Credential-free `SSHExecutor` (no `-i`, no host-key overrides) | `SSHExecutor` |
| `charly/deploy_executor.go` | `ShellExecutor` — local shell venue | `ShellExecutor` |
| `sdk/vmshared/hostdistro.go` | Detect host distro from `/etc/os-release`; glibc preflight | `HostDistro`, `DetectHostDistro`, `DetectHostGlibc`, `CompareGlibc`, `distroIDAliases` |
| `charly/install_ledger.go` | Flock-serialized JSON ledger at `~/.config/opencharly/installed/` | `LedgerPaths`, `LedgerLock`, `DeployRecord`, `CandyRecord`, `StepRecord`, `AcquireLedgerLock`, `AddCandyDeployment`, `RemoveCandyDeployment` |
| `charly/builder_run.go` | `podman run <builder>` wrapper for compile-needing layers | `BuilderRun`, `BuilderRunOpts`, `UserScopeBindMounts`, `UserScopeEnv` |
| `charly/shell_profile.go` | bash/zsh/fish detection + managed-block fencing + env.d I/O | `ShellKind`, `DetectLoginShell`, `EnvdDir`, `WriteEnvdFile`, `RemoveEnvdFile`, `ManagedBlockBody`, `RemoveManagedBlockAt` (the per-candy `shell_snippet:` teardown strip, called by `reverseRemoveManaged`), `ShellInitFilePath` (the block-SPLICE itself is kit's, `sdk/kit/profile.go`) |
| `charly/reverse_ops.go` | Execute `ReverseOp` slices in LIFO order via per-kind handlers + render each `ReverseOpPackageRemove`'s host removal command from the format's `uninstall_template` at record time | `runReverseOps`, `ReverseExecutor` interface, 15 reverse handlers, `fillReverseUninstallCmds` (called by `externalDeployTarget.recordDeploy` before ledger-persist — the aur builder emits an EMPTY `UninstallCmd` and defers to this host render; `reversePackageRemove` errors loudly on an empty command at teardown) |

**Managed block is written by the deploy walk's finalizer.** The env.d-sourcing block is written by `kit.WalkPlans`'s finalizer (`ensureVenueManagedBlock`) over the served executor — `GetFile` the existing rc, merge the fenced block, `PutFile` it back — for BOTH the external `local:` deploy (the host executor) AND the external `vm:` deploy (the guest `SSHExecutor`, so it lands on the guest fs). The shared body/path helpers stay in `shell_profile.go` (`ManagedBlockBody`, `ShellInitFilePath`); the block-splice itself is kit's (`sdk/kit/profile.go`); the plugin renders the equivalent via the kit primitives (`sdk/kit/profile.go`). The env.d-sourcing global block's teardown is the symmetric concern of that same walk; the per-candy `shell_snippet:` block is stripped on teardown by `reverseRemoveManaged` → `RemoveManagedBlockAt` (local) or its rendered in-place strip script (remote). `home` is the DESTINATION user's home — the guest home for a VM deploy (see `/charly-internals:vm-deploy-target`).
| `charly/service_render.go` | Render `ServiceEntry` → systemd unit / supervisord INI | `ServiceEntry`, `ServiceOverrides`, `RenderService`, `RenderedService` |
| `charly/deploy_ref.go` | Unified 4-form ref resolver | `DeployRef`, `RefKind`, `RefSource`, `ResolveDeployRef`, `classifyYAMLFile` |

## Credential-free SSHExecutor

`SSHExecutor` carries `User`, `Host`, `Port`, `Args`, `ConnectTimeout` — no `KeyPath`, no `KnownHostsFile`, no host-key overrides. `sshBaseArgs` emits only `-o LogLevel=ERROR` + `-o ConnectTimeout=…` plus optional `-p <port>` plus the deployment's pass-through `Args` plus the destination. `ssh(1)` reads `~/.ssh/config` + `ssh-agent` for everything else.

For VM destinations the Host field is the managed alias `charly-<vmname>`, written into `~/.config/charly/ssh_config` by `charly vm create`. Both `User` and `Port` are left empty — the alias's Host stanza supplies them.

## Managed ssh-config fragment

Pattern mirrors `charly/shell_profile.go` (the env.d managed block in `~/.profile` / `~/.zshenv` / `~/.config/fish/conf.d/opencharly.fish`):

- Fence markers: `# opencharly:begin (managed by charly; do not edit inside this block)` … `# opencharly:end`.
- `WriteVmSshStanza` writes/replaces a Host stanza inside the managed block at `~/.config/charly/ssh_config`. Multiple stanzas coexist, sorted by alias for deterministic output.
- `EnsureSshConfigInclude` ensures `Include ~/.config/charly/ssh_config` is present in `~/.ssh/config` (also fenced).
- `RemoveVmSshStanza` returns the count of remaining stanzas; when zero the fragment file is deleted.
- `RemoveSshConfigInclude` strips the Include line; when `~/.ssh/config` becomes empty after stripping, the file is deleted.
- `VmSshAlias("check-arch-vm")` → `"charly-check-arch-vm"`. Unique within the managed fragment.

## Ledger at `~/.config/opencharly/installed/`

Every target:local deploy writes a `DeployRecord` and per-layer `CandyRecord`s with `deployed_by:` refcount semantics. See the file map above for the JSON shapes.

Each record is **egress-validated** (`ValidateEgressValue` against `#DeployRecord` / `#CandyRecord`) before the JSON is written — on the host (`writeJSONAtomic`) and guest (`*Via` executor heredoc) paths alike — so a record missing its identity/time fields fails the deploy instead of silently corrupting teardown. Owned by `/charly-internals:egress`.

## Cross-References

- `/charly-internals:install-plan` — the IR these files support; full step-kind catalogue.
- `/charly-internals:go` — overall Go code map; Kong framework; mode-purity invariant.
- `/charly-local:local-deploy` — user-facing target:local surface.
- `/charly-core:deploy` — command family overview.
- `/charly-image:layer` — unified `service:` schema authored by layer authors.

## When to Use This Skill

**MUST be invoked** when reading or modifying any of the listed files; when debugging target:local ledger state or ssh-config fragment behavior; when adding a new `ReverseOpKind` handler, a new shell to the detection map, or a new distro ID alias; or when extending the ref resolver to accept a new ref form.
