---
name: charly-update
description: |
  Update image and restart service with data sync.
  MUST be invoked before any work involving: charly update command, pulling new image versions, data seeding, force-seed, or updating deployed services.
  Named `charly-update` (not `update`) to disambiguate from Claude Code's built-in `/update`/`/upgrade` slash commands.
---

# charly update -- Update Image and Restart

## Overview

Redeploy the current artifact and restart the service — for EVERY deploy kind through ONE codepath. `charly update <name>` resolves the deploy via `ResolveTarget` and calls `LifecycleTarget.Rebuild` (`charly/unified_targets_*.go`); there is no per-kind update code. The unified contract is **redeploy the current artifact + restart by default; `--build` rebuilds the artifact first** — realized per substrate: pod → `deploy add → config → start` (`--build` rebuilds the image); vm → destroy→create the domain (reuse the qcow2 disk unless `--build`) **then re-apply the deploy node's layers idempotently** via the shared `deploy add` path (so a config change — a newly-added layer or nested pod — takes effect on the rebuilt guest, exactly like local/pod); local → re-apply layers idempotently. All three live substrates end in the SAME `charly bundle add <node>` layer-apply step. k8s has no live runtime to rebuild (apply it via `kubectl apply -k`), so `charly update <k8s>` errors uniformly. Data sync uses MERGE mode by default — adds new files without overwriting existing user modifications.

**`charly update` does NOT auto-pull.** It redeploys the image already in local storage. To advance a deploy to a newer published image, `charly box pull <ref>` first, then `charly update`; or `charly update --build` to rebuild locally. (This consistency with vm's reuse-disk default replaced the former pod-only auto-pull, so `charly update` behaves identically across kinds.) See `/charly-core:deploy` for the unified command family and `/charly-local:local-deploy` for host-target specifics.

**`charly update` obeys an EXPLICIT invocation on ANY target.** It does NOT refuse a non-`disposable: true` deploy — for a target that is neither disposable nor ephemeral it prints a one-line transparency note (`noteUpdateDisposability`, naming the deploy key + lifecycle, so the operator can catch a mistyped name) and proceeds with the rebuild. The `disposable:` flag stays load-bearing as the authorization for UNATTENDED autonomous destroy + rebuild (the project rulebook R10 (`AGENTS.md` / `CLAUDE.md`)) and for the check-runner's unattended fresh-rebuild (`validateCheckBeds`); it does NOT gate this explicitly-invoked verb. See `/charly-internals:disposable`.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Update | `charly update <image>` | Pull new image, seed data, restart |
| Skip data sync | `charly update <image> --no-seed` | Pull and restart without data sync |
| Force overwrite | `charly update <image> --force-seed` | Overwrite existing data (cp -a) |
| Build instead of pull | `charly update <image> --build` | Build image locally before restart |
| Specific tag | `charly update <image> --tag v2.0` | Update to a specific tag |
| Named instance | `charly update <image> -i INSTANCE` | Update a named instance |
| Cross-image data | `charly update <image> --data-from <other>` | Seed data from a different image |

## Data Sync Modes

| Flag | Mode | Behavior |
|------|------|----------|
| `--seed` (default) | MERGE | `cp -an` -- adds new files, preserves existing |
| `--no-seed` | SKIP | No data sync, just pull and restart |
| `--force-seed` | OVERWRITE | `cp -a` -- overwrites all existing data |

## Usage

### Standard Update

```bash
# Pull latest image, merge new data files, restart
charly update jupyter
```

### Build and Update

```bash
# Build locally then update
charly update jupyter --build
```

### Force Data Reset

```bash
# Overwrite all data with fresh image defaults
charly update jupyter --force-seed
```

### Cross-Image Data Source

```bash
# Use data layers from a different image
charly update jupyter --data-from jupyter-custom
```

### Per-Instance Update with Volume Preservation

```bash
charly update selkies-desktop -i 82.23.94.69
```

When using `-i INSTANCE`, the update operates on a single named instance. The
container is destroyed and recreated from the new image, but the per-instance named
volumes are reattached:

- `charly-selkies-desktop-82.23.94.69-chrome-data` → `/home/user/.chrome-debug`
- `charly-selkies-desktop-82.23.94.69-selkies-config` → `/home/user/.config/selkies`

User-side state in those volumes (Chrome cookies, profile, history, selkies client
settings) **survives the restart**. The cgroup is recreated fresh, so any in-memory
state — including any leaked memfd-backed shmem from the old container — is released.

To roll a fleet of instances forward, loop the per-instance update:
`for ip in ...; do charly update selkies-desktop -i $ip; done` — each active
streaming session resumes cleanly on the new image with its per-instance
volume state intact.

### Rollback to a previous CalVer tag

Previous CalVer-tagged images stay in local storage after each `charly box build`
(retention: `defaults.keep_images`, see `/charly-core:clean`). To roll back:

```bash
# Find the previous tag (newest first; the (in use) marker shows the live one)
charly box list tags selkies-desktop

# Re-deploy the previous tag — repins + restarts through the unified update path
charly update selkies-desktop --tag 2026.102.1933
# or per-instance:
charly update selkies-desktop -i 82.23.94.69 --tag 2026.102.1933
```

This is fast (no network round-trip; `charly update` redeploys from local
storage). The pinned `tag:` persists in the per-host overlay until the next
`charly update --tag <newer>` advances it.

## Behavior by Mode

### Quadlet Mode

1. Pull/build new image
2. Sync data from data candies into the image's volumes — both bind mounts and podman named volumes (if `--seed`)
3. `systemctl --user restart charly-<image>.service`
4. Update `charly.yml` with new `data_source`

### Direct Mode

1. Pull/build new image
2. Sync data from data candies into the image's volumes (if `--seed`)
3. Print restart instructions (manual restart required)

## Data Seeding

Data candies (candies that declare a `data:` block in `charly.yml`) ship
starter content that gets copied into the runtime volume on first
deployment. Examples: `notebook-templates` ships
`getting-started.ipynb` into jupyter's `workspace` volume;
`notebook-finetuning` ships a set of Unsloth notebooks into
`jupyter-ml-notebook`.

### Which volumes get seeded

Both backings are seeded:

- **Bind-mounted volumes** (`type: bind` in `charly.yml`) — the
  staged data is copied into the host directory via a throwaway
  `podman run` with `--userns=keep-id` so the files end up owned by
  the real host user.
- **Named volumes** (the default when no `type: bind` override is set)
  — the staged data is copied via `podman run -v <name>:/seed`
  *without* `--userns=keep-id`, so the files match the rootless
  subuid identity the runtime container uses.

### Mode semantics

- **`DataProvisionInitial`** (the default for `charly config`) — only
  seeds when the target volume is empty. For bind mounts, checks the
  per-entry subdirectory; for named volumes, checks the volume root
  via `podman volume inspect`.
- **`DataProvisionMerge`** (the default for `charly update --seed`) —
  always runs `cp -an`, which adds new files without overwriting
  existing ones. Safe on non-empty targets.
- **`DataProvisionForce`** (`charly update --force-seed` or
  `charly config --force-seed`) — runs `cp -a` unconditionally,
  overwriting existing files.

When seeding populates a named volume, the output shows
`  <volume> (named): provisioning from /data/<volume>/ ...`.

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:charly-config` -- initial deployment setup
- `/charly-core:start` -- start a service
- `/charly-build:build` -- building images locally
- `/charly-core:charly-status` -- check service status after update

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM in vm.yml.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See the project rulebook R1–R10.
