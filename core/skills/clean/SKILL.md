---
name: clean
description: |
  Prune reusable build artifacts to defaults: retention (images, check runs) and
  sweep one-time makepkg leftovers.
  MUST be invoked before any work involving: charly clean, build-artifact retention,
  keep_images / keep_check_runs, image-tag pruning, or .check run cleanup.
---

# charly clean -- Build-artifact retention + cleanup

## Overview

`charly clean` reclaims disk by applying the project's configured retention to
**reusable** build artifacts and removing **one-time** transient leftovers. It is
the on-demand counterpart to the auto-pruning that runs after `charly box build`
and `charly check run`.

`charly clean` is a **compiled-in COMMAND-class plugin** (`candy/plugin-clean`, `command:clean`) that OWNS the command. The plugin owns the flag grammar (`--dry-run` / `--images` / `--check` / `--deep` / `--keep` / `--invalidate`), the category orchestration, the report output, and the local `pkg/arch` makepkg sweep (`cleanMakepkgArtifacts`, a single-caller file op moved into the plugin). The **shared retention engine** — `pruneImagesByRetention`, `pruneCheckRuns`, `pruneBuildCandyDirs`, `invalidateImageTags`, `pruneDeepDanglingImages`, and the charly-labeled image-tag CalVer/label inventory — STAYS in core (`charly/retention.go`) because it is multi-caller: `charly box build`, `charly check run`, and `charly box list tags` all use it. The plugin reaches it through the generic **"retention" `HostBuild` seam** (`charly/host_build_retention.go`, `spec.RetentionRequest` → `spec.RetentionReply`), which resolves the project's `keep_images` / `keep_check_runs` defaults (`ResolveRuntime` + `LoadConfig`) host-side. clean is **compiled-in** (`charly/charly.yml` `compiled_plugins:`) because its `Invoke(OpRun)` needs the in-proc reverse channel — threaded by `dispatchInProcCommand` ("Seam A") — to call `HostBuild`; the out-of-process `CliMain` path has no reverse channel and errors. This is the same "plugin owns the logic + generic seams for the core-coupled bits" doctrine the vm + pod deploy plugins established — no hidden core-command forward, and no plugin-specific command logic left in core.

Two artifact classes, two policies (operator principle):

- **One-time / transient → always cleaned immediately.** makepkg leftovers under
  `pkg/arch` (`src/`, `pkg/`, `*.pkg.tar.zst`, `*.log`) from a manual bare-host
  `makepkg` invocation (native-package builds normally run containerized via `task
  pkg:arch` → `charly box pkg`, which never touches this tree) — `charly clean`
  sweeps any such leftover.
- **Reusable → keep-last-N, configurable in `defaults:`.** Container image tags
  and `.check` run output. Retention is set in `charly.yml` `defaults:` and
  applied automatically at creation; `charly clean` applies it on demand.

## Config (charly.yml `defaults:`)

```yaml
defaults:
  keep_images: 3      # newest CalVer tags to keep per image after `charly box build`
  keep_check_runs: 3   # newest run dirs to keep per bed/score after `charly check run`
```

`0` (or absent → built-in fallback `0`) **disables** that retention. The repo
opts in; third-party configs get no surprise pruning until they set a value.

## Commands

```bash
charly clean              # apply retention now: prune images + check runs + makepkg leftovers
charly clean --dry-run    # print everything that WOULD be removed; touch nothing
charly clean --images     # only image-tag retention
charly clean --check       # only check-run retention
charly clean --deep        # store-wide untagged/dangling-image purge (see below); runs ONLY
                           # this category unless combined with --images/--check
charly clean --deep --dry-run   # the safe default probe: report the would-remove count +
                                # total reclaimable bytes for --deep; touch nothing
charly clean --keep N     # override the retention count for this run (0 = use defaults:)
charly clean --invalidate '<glob>'   # remove charly-labeled image tags matching the glob
                                     # (full ref or last segment; in-use skipped; runs ONLY this)
```

With neither `--images` nor `--check` nor `--deep`, the three DEFAULT categories run (images +
check + makepkg) — unchanged, `--deep` NEVER fires implicitly. `--keep N` overrides both the
image and check-run retention counts for the invocation (it does not affect `--deep`, which has
no keep-N — it purges every untagged image).

**`--deep` — the store-wide untagged/dangling-image purge.** The default image-tag sweep above
only ever touches images carrying the `ai.opencharly.box` label. A multi-stage build's
INTERMEDIATE stage images (`FROM ... AS stagename`) are never labeled — `WriteLabels` stamps the
`ai.opencharly.*` labels only on the FINAL stage — so they accumulate as unlabeled dangling
images completely invisible to the default sweep, wasting disk and confounding build-corruption
diagnosis on a host with many builds behind it. `charly clean --deep` closes this gap: it lists
EVERY untagged (dangling) image in local storage, charly-labeled or not, and removes each one
(`rmi` without `-f`, so any image still referenced by a container or a kept tag is safely
skipped — the same backstop the default sweep relies on). It never runs mid-build (the same
live-build guard the default dangling sweep uses) and never fires implicitly on a plain `charly
clean` — it is strictly opt-in. Removing a dangling image also frees any layer blobs it alone
held (the engine's overlay storage GCs an unreferenced layer once its last referencing image is
gone), so `--deep` is effectively a dangling-image-plus-unused-layer prune in one pass.
`--deep --dry-run` reports the would-remove image count plus the total reclaimable bytes
(summed from each candidate's reported storage size) without touching anything — the safe
default probe before running it for real.

## What gets pruned (and what never does)

**Image-tag retention** (`keep_images`): images are grouped by the
`ai.opencharly.box` label and ordered by the `ai.opencharly.version`
CalVer label; all but the newest N per group are `podman rmi`'d. **Safety**: any
image referenced by a container (`podman ps -a`, including stopped/quadlet
deploys) is skipped, and `rmi` runs WITHOUT `-f` so the engine refuses any
still-referenced image as a backstop. Non-charly images (no `ai.opencharly.box`
label) and images with an unparseable version are never touched.

**Check-run retention** (`keep_check_runs`): each `.check/<bed|score>/` dir is
trimmed to the newest N run artifacts — CalVer-named run dirs (bed runs),
`runs/<id>/` dirs (score iterations), and `result-<calver>.yml` files.
**`NOTES.md` is ALWAYS preserved** (it's the durable Syncthing-replicated harness
memory), as is any other non-run file.

**makepkg sweep**: removes `pkg/arch/{src,pkg,*.pkg.tar.zst,*.log}` (the package
is already installed via pacman — pure transient waste).

`--dry-run` is best-effort: it lists prune candidates but cannot see "external"
build containers (buildah intermediates `podman ps -a` doesn't list), so an
image held by one is listed yet safely skipped at removal time (the `rmi`
backstop refuses it). The real run silently retains such in-use images.

## Auto-prune at creation

The same retention runs automatically (no flag needed):

- After `charly box build` (push runs excluded) → `keep_images`.
- After `charly check run` (any path: bed / score) → `keep_check_runs`,
  after the new run's output is written so the newest run is kept.

`charly clean` exists for on-demand sweeps and to clear a pre-existing backlog.

## Out of scope

VM disk images (`output/`, `image/*/output/`) are single products per type
(overwritten on rebuild, not accumulated) — remove them on demand with
`charly vm destroy --disk`. The VM raw intermediate is already auto-cleaned during
the qcow2 build.

## Implementation

`candy/plugin-clean/` — the command plugin that OWNS `charly clean`: `command.go`
(flag grammar + category orchestration via `cleanCategories` + `cleanMakepkgArtifacts` +
`hostRetention`, which calls the seam), `provider.go` (`Invoke(OpRun)`, the compiled-in dispatch
surface), `plugin.go` (`NewProvider` / `NewMeta` / `CliMain`). The **shared retention engine**
stays in core: `charly/retention.go` holds `pruneImagesByRetention`, `pruneCheckRuns`,
`pruneBuildCandyDirs`, and the `charlyImageTags` inventory (`invalidateImageTags` lives with
`charly box list tags` in `charly/volume_cp_tags_cmd.go`). `--deep` shares its engine with the
default charly-labeled dangling sweep via `pruneDanglingImages`/`selectDanglingImages`
(`charly/retention.go`) parameterized by an `onlyCharly` bool: `pruneDanglingCharlyImages`
(onlyCharly=true, the default sweep) and `pruneDeepDanglingImages` (onlyCharly=false, `--deep`)
are both thin wrappers over the ONE shared selection + removal engine (R3 — no duplicated
listing/removal logic between the two categories). The plugin reaches it via the generic
"retention" `HostBuild` seam — `charly/host_build_retention.go` (`hostBuildRetention`,
registered as `retentionBuilderKind = "retention"`, resolving defaults with `ResolveRuntime`
+ `LoadConfig`); the compiled-in in-proc reverse channel is threaded by `dispatchInProcCommand`
(`charly/provider_command_external.go`).
Auto-prune hooks: `BuildCmd.Run` (`charly/build.go`) fires the `keep_images`
prune; the `charly check run` prune is driven by the `command:check` plugin's
harness (`candy/plugin-check`) over the same generic `retention` `HostBuild` seam.
Retention keys live on `BoxConfig`
(`charly/config.go`), merged via `mergeBoxConfig` (`charly/unified.go`), validated in
`validateBuildTunables` (`charly/validate.go`).

## Cross-References

- `/charly-build:build` — `charly box build` + the `keep_images` auto-prune.
- `/charly-check:check` — `charly check run` + the `keep_check_runs` auto-prune.
- `/charly-vm:vm` — `charly vm destroy --disk` for VM disk removal.
- `/charly-image:image` — the `defaults:` block where retention keys live.
