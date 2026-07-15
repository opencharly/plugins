---
name: charly-cachyos
description: |
  Operator CachyOS workstation profile — a kind:local template plus a host:local
  deploy that installs the full dev stack (30 candies) onto a CachyOS host via
  ShellExecutor. Lives in the opencharly/distro-cachyos submodule.
  MUST be invoked before editing or applying the charly-cachyos workstation profile.
---

# charly-cachyos

The operator's CachyOS developer-workstation profile: a `kind: local` template
(`charly-cachyos-app`) plus a `host: local` deploy (`charly-cachyos`, the
deploying entry) that applies a kitchen-sink dev stack directly to the
current machine via `ShellExecutor` — no SSH, no VM, no container.

It lives in the **`opencharly/distro-cachyos`** repo (git submodule at
**`box/cachyos`**), in that repo's single `charly.yml` — both the
`kind: local` template (`charly-cachyos-app`) and the `charly-cachyos` `local:` deploy
that deploys it. The repo also carries the `cachyos-gpu` deploy — the
**persistent** operator GPU-workstation VM (`vm: { from: cachyos-gpu-workstation-vm }`,
**not** `disposable`; see `/charly-vm:cachyos-bootstrap-vm`) — so `charly-cachyos` is no longer
the only non-disposable deploy there; every disposable test bed is a
`disposable: true` deploy. Apply it with:

```bash
charly -C box/cachyos update charly-cachyos
# or, anywhere:
charly --repo opencharly/distro-cachyos update charly-cachyos
```

## What it installs

30 candies. Most are pulled from the main repo by **git reference**
(`@github.com/opencharly/charly/candy/<name>:<tag>`); the cachyos-exclusive
`ghostty`, `keepassxc-keyring`, and `wheel-nopasswd` are vendored locally in this
repo's `candy/` (resolved via its `discover:` block):

`wheel-nopasswd`, `yay`, `dev-tools`, `gh`, `pre-commit`, `tmux`, `direnv`,
`gnupg`, `keepassxc`, `keepassxc-keyring`, `tailscale`, `tailscale-up`,
`build-toolchain`, `golang`, `rust`, `nodejs`, `uv`, `claude-code`, `codex`,
`gemini`, `oracle`, `forgecode`, `devops-tools`, `docker-ce`, `kubernetes`,
`vscode`, `ghostty`, `chrome`, `nvidia`, `charly`.

## Key fields

| Field | Value |
|---|---|
| `install_opts.builder_image` | `ghcr.io/opencharly/arch-builder:2026.122.2252` (OCI ref, not a candy) |
| `install_opts` | with_service, allow_repo_changes, allow_root_tasks all true |
| `env` | `EDITOR=nvim`, `PAGER=less` |
| `disposable` (deploy) | `true` — `charly update charly-cachyos` is authorized |

## Deploy-scope check probes

- `passwordless-sudo-host` — `sudo -n true` (wheel-nopasswd candy must have run)
- `nvidia-ctk-present` — `command -v nvidia-ctk`
- `nvidia-cdi-spec` — `/etc/cdi/nvidia.yaml` exists

Both `nvidia-*` probes gate on an active host NVIDIA driver
(`[ -e /dev/nvidiactl ] || nvidia-smi`) and pass with an N/A note on a
card-less or VFIO-passthrough host, so the profile applies cleanly anywhere.

## Composition-by-reference note

`charly-cachyos-app`'s remote candy refs are collected and materialized by the
same `CollectRemoteRefs` walk as box candy refs: the walk collects the candy
refs of the ROOT project's own `kind: local` templates (the cachyos repo is the
root here), so `charly box validate` / `charly update charly-cachyos` resolve the github-ref'd
candies. (Collection is reachability-scoped — a namespace's `kind:local`
templates, imported only as a dependency, are NOT collected by an importer; only
the root's own locals are. See `/charly-internals:go` "Remote-layer resolver".)

## Cross-References

- `/charly-local:local-spec` — `kind: local` template authoring reference
- `/charly-local:local-deploy` — the `target: local` deployment surface
- `/charly-distros:cachyos` — the CachyOS base of the same family
- `/charly-core:deploy` — bundle entry semantics (globally-unique names within a document: the `charly-cachyos` bundle deploys the suffixed `charly-cachyos-app` `kind: local` template)

## When to Use This Skill

**MUST be invoked** when editing or applying the charly-cachyos workstation profile,
or reasoning about the kind:local remote-candy-ref machinery. Invoke BEFORE
reading source code or launching Explore agents.
