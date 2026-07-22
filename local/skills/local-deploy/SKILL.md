---
name: local-deploy
description: |
  MUST be invoked before any work involving: `target: local` deployments, the Ansible-style `host:` destination field (literal `local` for direct shell, anything else routes through ssh(1) reading `~/.ssh/config` + ssh-agent), the `local:` substrate kind and its `from:` template reference, the `user:` and `ssh_args:` Ansible-shaped overrides, the managed `~/.config/charly/ssh_config` fragment, the install ledger at `~/.config/opencharly/installed/`, ReverseOp teardown, or the `--with-services`/`--allow-repo-changes`/`--allow-root-tasks` gates.
---

# Local Deploy — Applying Candies Directly to a Linux Filesystem

## Overview

`target: local` deployments apply a box or candy's install recipe directly to a Linux filesystem instead of baking it into a container image. The destination is named by the deployment's `host:` field (Ansible-style):

- `host: local` (literal) or absent → `ShellExecutor` (run on this machine).
- Anything else → `SSHExecutor` (ssh(1) reads `~/.ssh/config` + ssh-agent for keys, host-key checking, options).

The same `InstallPlan` IR that drives container deploys (via the candy `plugin-deploy-pod`, incl. `add_candy:` overlay synthesis through `deploykit.OCITarget`) is consumed by the external `deploy:local` plugin (`candy/plugin-deploy-local`), which `pluginDeployTarget` (`charly/unified_targets.go`, S3b) hands the plan — via `candy/plugin-bundle`'s `Invoke(OpDeployDispatch)` reaching the substrate's own `InvokeProvider` — over the executor reverse channel; the plugin walks it via the shared out-of-process walk (`sdk/kit.WalkPlans`), translating each IR step into shell commands, `podman run <builder>` invocations for compile-needing work, and systemd unit writes. The step kinds the plugin cannot render itself (`BuilderStep`, `LocalPkgInstallStep`, `SystemPackagesStep`, act-verb `OpStep`, `ExternalPluginStep`) are driven on the HOST via the `RunHostStep` reverse-channel RPC. (`charly box build` itself emits Containerfiles via the separate `WriteCandySteps` → `EmitTasks` generator in `sdk/deploykit` (relocated from `charly/generate.go` in #67), not the IR — see `/charly-internals:install-plan`.)

The deploy applies host packages + configs ONLY. Container images required for `charly check run` / `charly check live` are ensured by the check preflight (see `/charly-check:check` "Image preflight"), not by the deploy. Deploys (any target) emit zero image-pull / image-build steps — that's the project rulebook "Deploy fetches NOTHING speculative" Key Rule (`AGENTS.md` / `CLAUDE.md`), codified at the type level. Migration of legacy `image:` blocks: `charly migrate` (idempotent).

Use cases:
- Installing a focused tool set (ripgrep + uv + direnv) on your workstation without a container.
- Iterating on a candy locally, then baking it into a box.
- Pushing a profile to a remote machine over SSH (CI runner, lab box, bastion) without ad-hoc shell scripting.

## SSH config + agent are the configuration

charly contains **zero** custom SSH-key resolution. We do not read `~/.ssh/config`, we do not detect ssh-agent, we do not prompt for keys. `ssh(1)` does it all. Configure your destinations via `~/.ssh/config` `Host` stanzas, load keys into `ssh-agent`, and `charly` shells out to `ssh` with no `-i` / `-o StrictHostKeyChecking=` / `-o UserKnownHostsFile=` overrides.

For VM destinations, `charly vm create <name>` writes a managed Host stanza into `~/.config/charly/ssh_config` (one per VM, fenced with `# opencharly:begin` markers) and ensures your `~/.ssh/config` has `Include ~/.config/charly/ssh_config` (also managed). After that, `ssh charly-<vmname>` works from any terminal — and the local deploy path constructs `&SSHExecutor{Host: "charly-<vmname>"}` (via `rootExecutorForDeployNode`) with no User/Port/Key; ssh(1) resolves them from the config. The alias is `charly-<VmDomainIdentity(deploy)>` — keyed by the DEPLOY name (a direct `charly vm create <entity>` deploy name IS the entity; a `vm:` bed's alias is `charly-<bed>`), so sibling beds sharing one `kind:vm` entity get distinct aliases (P33).

## Quick Reference

| Action | Command |
|---|---|
| Direct local | `charly bundle add my-laptop` (`host: local` is the default) |
| SSH to remote | `charly bundle add ci-3` with `host: user@ci-3.lan` in charly.yml |
| Reference a template | `from: dev-workstation` inside the `local:` node |
| Tear down | `charly bundle del <name>` |
| Tear down, keep repo changes | `charly bundle del <name> --keep-repo-changes` |

## Three DIFFERENT remote surfaces — do not conflate them

charly exposes three distinct mechanisms. Picking the wrong one silently changes which
executor runs, and therefore what a check bed actually proves.

| Mechanism | What it is | Executor | Where the work happens |
|---|---|---|---|
| `local: {host: user@machine}` | a **deploy field** — apply candies TO a remote machine | `SSHExecutor` | that machine (driven from here) |
| a `local:` node **nested under** a `vm:`/`pod:` node | **tree position** — deploy INTO the enclosing venue; the child carries NO `host:` | `NestedExecutor` over the parent venue | inside the enclosing deployment |
| `charly --host <alias\|user@host[:port]> <verb>` | a **global CLI flag** — re-exec the whole COMMAND remotely | n/a (a fresh `charly` runs there) | on the remote machine |

**`charly --host` is a command-transport flag, not a deploy field** (`charly/host_exec.go`).
It shells out to `ssh <target> charly <argv>` and propagates the exit code; stdin/stdout/stderr
pipe straight through, so `~/.ssh/config`, agent forwarding, and ControlMaster all apply.

- Alias resolution: a value containing `@` or `.` is used verbatim; otherwise
  `charly settings set hosts.<alias> <target>` is consulted, and failing that the raw string
  is handed to `ssh(1)` (so a `Host` stanza — e.g. the `charly-<vmname>` alias that
  `charly vm create` writes — just works).
- `settings`, `version`, and `ssh` are **LocalOnly**: they manage the local installation and
  are never re-execed.
- `buildRemoteArgv` **strips `--host`, `--dir`/`-C`, and `--repo`** before shipping argv, so
  the remote `charly` starts in the SSH cwd and must locate its project itself — via its own
  cwd, or `CHARLY_PROJECT_DIR` / `CHARLY_PROJECT_REPO` in the remote environment. Note that
  `ssh host cmd` is a NON-interactive shell: it sources neither `/etc/profile` nor `~/.bashrc`.
  `/etc/environment` DOES reach it (pam_env, via `UsePAM`), so that is where such a variable
  belongs on the guest.

**To run a `local:` check bed inside a VM, use NESTING** — it keeps the `local:` authoring
shape (same template, same candies, same `plan:`) and confines every write to the guest, and
the enclosing bed owns its lifecycle. Canonical example: `check-arch-vm` → `arch-host` in
`box/arch/charly.yml`. See `/charly-core:deploy` "Deploy-into nesting".

**But be precise about what moving a bed COSTS.** `ShellExecutor` runs only for a TOP-LEVEL
`local:` deploy with `host: local` (or absent). **All three remote surfaces above bypass it** —
nesting included: a nested child runs on `NestedExecutor` over the parent venue (for a `vm:`
parent, the guest `SSHExecutor`), and `RootExecutorForDeployNode` explicitly "does NOT handle
the nested-inside-a-parent case" (`sdk/deploykit/deploy_chain.go`). So relocating a
`host: local` bed — by nesting, by a `host:` retarget, or by `charly --host` — **deletes its
`ShellExecutor` + `HostDeployTarget` coverage**. `check-local` declares itself the *"sole proof
of the kind:local layer-application path via ShellExecutor + HostDeployTarget"*; that coverage
cannot be relocated, only replaced deliberately by another top-level `host: local` bed.

## `host:` destination semantics

A host/remote deploy MUST be authored as the `host:` FIELD on a `local:` deploy — `local: {from: <template>, host: <user@machine>}`. The `host:` field is a SCALAR on the `local:` substrate node; there is NO standalone `host:` venue KIND, and authoring a `host:` node is a hard load error.

Reserved literal: `local`. Anything else (including `localhost`, `127.0.0.1`) goes through SSH.

**A top-level `local:` deploy with `host: local` (or `host:` absent) writes to the OPERATOR'S
machine** — including one marked `disposable: true`, which makes it a check bed a roster will
discover and run. Nest it under a disposable `vm:` bed when the writes must stay in a guest.

```yaml
# Each deployment is a name-first deploy: the `local:` substrate kind at
# the edge, `from:` selects the template, and `host:` selects direct shell vs SSH.

# Direct local — host: omitted == "local". Deploy data (add_candy,
# install_opts, …) lives inline in the substrate node.
my-laptop:
  local:
    from: dev-workstation
    add_candy: [sshkeys]

# Explicit local sentinel.
my-laptop-explicit:
  local:
    from: dev-workstation
    host: local

# SSH to remote machine (ssh-config + agent supply credentials).
ci-runner-3:
  local:
    from: ci-runner
    host: ubuntu@ci-runner-3.lan

# SSH with explicit port.
bastion:
  local:
    from: dev-workstation
    host: admin@bastion.example.com:2222

# SSH to loopback for testing the SSH path.
ssh-self-test:
  local:
    from: dev-workstation
    host: localhost
```

## `user:` and `ssh_args:` — Ansible-style overrides

Two pass-through fields mirror Ansible's per-host overrides:

```yaml
# Explicit user override (Ansible's ansible_user). Used when host: has
# no "@" prefix. Cleaner than embedding the user in host: when the
# destination is an ssh-config alias. host: and user: are scalars, so
# they sit directly under the substrate kind.
workshop-laptop:
  local:
    from: dev-workstation
    host: workshop-laptop.lan
    user: alice

# ssh_args: passes options through to ssh(1) (Ansible's
# ansible_ssh_extra_args). Use sparingly — ssh-config Host stanzas are
# the right home for persistent options. ssh_args is a list, so it lives
# in its own child node.
via-bastion:
  local:
    from: dev-workstation
    host: target.internal
    user: ops
  via-bastion-ssh_args:
    ssh_args:
      - "-o"
      - "ProxyJump=ops@bastion.example.com"
```

**Precedence rule** for `user:` vs the inline `host: <user>@<machine>` form: the inline user wins (more-specific beats more-general). When both are set with different values, the validator emits an error — pick one. When both are absent, ssh(1) reads the `User` directive from `~/.ssh/config` or falls back to `$USER`.

## Setup: one-time `Include` line

The first `charly vm create` writes:
- A Host stanza into `~/.config/charly/ssh_config` (managed block, fenced).
- An `Include ~/.config/charly/ssh_config` line into your `~/.ssh/config` (also fenced).

If you prefer to manage your `~/.ssh/config` manually, add the Include line yourself before creating any VMs. `charly vm destroy` removes the matching stanza and, when the fragment is empty, removes the Include line too.

## Passwordless sudo on remote SSH targets

Remote `target: local` deploys assume **passwordless sudo** on the destination. We do not bridge interactive sudo prompts through the SSH session. Either: (a) configure `NOPASSWD` for your user on the remote, or (b) restrict the deploy to layers that don't require root (omit `--with-services`, omit packages that need `sudo dnf`).

## Gates (opt-in flags)

| Flag | Guards |
|---|---|
| `--with-services` | systemd unit writes; `systemctl enable --now` |
| `--allow-repo-changes` | `/etc/yum.repos.d/`, `/etc/apt/`, `/etc/pacman.conf` mutations |
| `--allow-root-tasks` | arbitrary `cmd: user: root` task bodies (opaque shell) |
| `--skip-incompatible` | skip candies without a destination-matching format section |
| `--builder-image <ref>` | override the compile builder image |
| `--yes` / `-y` | implies all three gates + skips sudo preflight |

## Validation

`charly box validate` checks every `target: local` deployment:

- `from: <name>` (inside the `local:` node) references a `kind: local` template that exists.
- `host:` field, when non-`local`, parses via `ParseSSHTarget`.
- `user:` and `ssh_args:` only meaningful when `host:` is non-`local` (otherwise error).
- `user:` redundancy: when `host: <inline>@<machine>` and `user:` are both set with different values, error.

## Cross-References

- `/charly-local:local-spec` — author-facing reference for `kind: local` templates.
- `/charly-internals:local-infra` — Go file map for the executor/ledger surface.
- `/charly-core:deploy` — parent command family.
- `/charly-image:layer` — `service:` schema rendered as systemd units on local-target deploys.
- `/charly-vm:vm` — managed ssh-config fragment writen on `charly vm create`.
- `/charly-check:check` — `--verify` re-runs candy `check:` against the deploy post-install.
- `/charly-internals:install-plan` — shared IR consumed by the external `deploy:local` plugin over the executor reverse channel.

## When to Use This Skill

**MUST be invoked** when the task involves `target: local`, the Ansible-style `host:` field, the `user:`/`ssh_args:` overrides, the managed ssh-config fragment, the install ledger, or ReverseOp teardown. Invoke this skill BEFORE reading Go source or launching Explore agents.
