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

`charly clean` is a **compiled-in COMMAND-class plugin** (`candy/plugin-clean`, `command:clean`) that OWNS the command AND (K1-alpha core-minimization) the **shared retention ENGINE** itself — `pruneImagesByRetention`, `pruneCheckRuns`, `pruneBuildCandyDirs`, `invalidateImageTags`, `pruneDeepDanglingImages`, and the charly-labeled image-tag CalVer/label inventory (`candy/plugin-clean/retention.go`), relocated from the former `charly/retention.go` since it has zero core-only dependencies (`kit.CalVer`/`kit.ListLocalImages`/`kit.BuildActivityDir` are all sdk-portable). The plugin owns the flag grammar (`--dry-run` / `--images` / `--check` / `--deep` / `--keep` / `--invalidate`), the category orchestration, the report output, and the local `pkg/arch` makepkg sweep (`cleanMakepkgArtifacts`, a single-caller file op moved into the plugin). `charly clean`'s own CLI calls the engine LOCALLY (no wire hop, same package). The other three callers — `charly box build`'s post-build prune, `charly box list tags`, and `charly check run`'s post-run prune (candy/plugin-check) — reach it via a new `verb:retention` capability (a `spec.RetentionRequest` → `spec.RetentionReply` Invoke), the SAME peer/core-adapter pattern verb:credential/verb:gpu/verb:tunnel already use: core's two callers (already running `LoadConfig` in-process) resolve `defaults.keep_images`/`keep_check_runs` themselves and pass the resolved ints in the request; plugin-check (a peer plugin, not core) reaches verb:retention via `InvokeProvider`. The ONE thing the plugin genuinely cannot compute itself is those SAME defaults, for its OWN CLI — fetched via the small **"retention-defaults" `HostBuild` seam** (`charly/host_build_retention_defaults.go`, resolving `ResolveRuntime` + `LoadConfig` host-side) — the ONE remaining call-back. clean is **compiled-in** (`charly/charly.yml` `compiled_plugins:`) because its `Invoke(OpRun)` needs the in-proc reverse channel — threaded by `dispatchInProcCommand` ("Seam A") — to call `HostBuild("retention-defaults")`; the out-of-process `CliMain` path has no reverse channel, so the categories needing a resolved keep-default (images/check/deep) error there — list/invalidate need no default and run standalone. This is the same "plugin owns the logic + generic seams for the core-coupled bits" doctrine the vm + pod deploy plugins established — no hidden core-command forward, and no plugin-specific command logic left in core.

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
                                # an UPPER-BOUND reclaimable-bytes figure for --deep; touch nothing
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
`--deep --dry-run` reports the would-remove image count plus an UPPER-BOUND reclaimable-bytes
figure (summed from each candidate's reported storage size) without touching anything — the safe
default probe before running it for real.

**The reclaimable-bytes figure is "up to", never a firm prediction.** Each image's reported
storage size counts EVERY layer it references, and dangling images routinely SHARE layers with
images that stay (retained tags, other dangling images) — removing an image frees only the
layers it held UNIQUELY, so actual disk freed is usually much less than the naive per-image sum.
RDD-verified live: a `--deep` purge removing 68 untagged images (3,552 → 3,484 images) reported
~92.6 GiB via this sum but freed only ~4.6 GiB of real disk (132.6 GB → 128 GB) — most of those
bytes stayed shared with the ~3,400 remaining (largely stale-tagged) images. Pair `--deep` with
`--invalidate` (which removes stale image TAGS, freeing whatever layers only they still held) to
get closer to the reported figure and reclaim more of the store.

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

`candy/plugin-clean/` — the command plugin that OWNS `charly clean` AND the shared retention
ENGINE: `command.go` (flag grammar + category orchestration via `cleanCategories` +
`cleanMakepkgArtifacts` + `fetchRetentionDefaults`, which calls the one remaining host seam),
`provider.go` (`Invoke`, dispatching by word — `"clean"` for the CLI, `"retention"` for the
engine — the compiled-in dispatch surface for both), `plugin.go` (`NewProvider` / `NewMeta`
advertising `command:clean` + `verb:retention` / `CliMain`), `retention.go` (the relocated
engine: `pruneImagesByRetention`, `pruneCheckRuns`, `pruneBuildCandyDirs`, `invalidateImageTags`,
`pruneDeepDanglingImages`, and the `charlyImageTags` inventory — all now in this package,
importing only `sdk/kit` + `sdk/spec`). `--deep` shares its engine with the default
charly-labeled dangling sweep via `pruneDanglingImages`/`selectDanglingImages`
(`candy/plugin-clean/retention.go`) parameterized by an `onlyCharly` bool: `pruneDanglingCharlyImages`
(onlyCharly=true, the default sweep) and `pruneDeepDanglingImages` (onlyCharly=false, `--deep`)
are both thin wrappers over the ONE shared selection + removal engine (R3 — no duplicated
listing/removal logic between the two categories). The engine is reached two ways: `charly
clean`'s own CLI calls `runRetention` in-package (no wire hop); the three OTHER callers reach
`verb:retention` — core's `BuildCmd.Run` (`charly/build.go`, via `charly/retention_plugin.go`'s
`pruneAfterBuild`, resolving `defaults.keep_images` itself and passing it pre-resolved) and
`charly box list tags` (`charly/volume_cp_tags_cmd.go`, via `retention_plugin.go`'s
`listCharlyImageTags`) resolve+Invoke the compiled-in provider directly (`providerRegistry.resolve
(ClassVerb, "retention")`); `charly check run`'s post-run prune (the `command:check` plugin's
harness, `candy/plugin-check`) reaches it over the PLUGIN↔PLUGIN `InvokeProvider` peer-dispatch
leg (F10) instead, since it is itself a plugin and cannot resolve the core registry directly.
Both non-core-adapter callers first fetch the resolved `defaults.keep_images`/`keep_check_runs`
via the small **"retention-defaults" `HostBuild` seam** (`charly/host_build_retention_defaults.go`,
resolving `ResolveRuntime` + `LoadConfig`) — the ONE thing the engine genuinely cannot compute
itself; the compiled-in in-proc reverse channel is threaded by `dispatchInProcCommand`
(`charly/provider_command_external.go`).
Retention keys live on `BoxConfig`
(`charly/config.go`), merged via `mergeBoxConfig` (`charly/unified.go`), validated in
`validateBuildTunables` (`charly/validate.go`).

## Cross-References

- `/charly-build:build` — `charly box build` + the `keep_images` auto-prune.
- `/charly-check:check` — `charly check run` + the `keep_check_runs` auto-prune.
- `/charly-vm:vm` — `charly vm destroy --disk` for VM disk removal.
- `/charly-image:image` — the `defaults:` block where retention keys live.
