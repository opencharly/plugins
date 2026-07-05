---
name: image
description: |
  MUST be invoked before any work involving: the `charly box` command family, box definitions in charly.yml, box inheritance, defaults, platforms, builder configuration, the box dependency graph, or the build/deploy scope boundary.
---

# charly box -- Family Overview + Image Composition

## Overview

`charly box` is the **only** command family that reads `charly.yml`. It groups
every build-mode operation (build, generate, validate, list, merge, new,
inspect, pull) under a single namespace. All other `charly` commands read
exclusively from OCI labels embedded into built images + `charly.yml` for
deployment overrides.

Build-mode operations live only under `charly box`. Top-level invocations like
`charly build`, `charly validate`, `charly list boxes`, or `charly inspect` return Kong's
`unexpected argument` error.

A **box** is an **image** — a named build target in `charly.yml`. Boxes compose
candies into container images with configurable defaults, inheritance chains,
platform targets, and builder configurations. The `charly` CLI resolves
dependencies, generates Containerfiles, and builds images in the correct
order.

**Authoring rule (MUST).** An IMAGE MUST be authored as a `candy:` node carrying
`base:` (an external base distro / OCI ref) **or** `from:` (a builder ref, e.g.
`from: builder:pacstrap`) — there is **no `box:` KIND**. A `candy:` node carrying
neither `base:` nor `from:` is a **LAYER** fragment (see `/charly-image:layer`).
The `charly box` COMMAND family (build / validate / generate / inspect / list /
merge / labels) is UNCHANGED — it operates on images (candies carrying `base:`/
`from:`); only the YAML `box:` KIND keyword was removed. The `box/<name>/` and
`candy/<name>/` discovery directories, and the `BoxConfig` / `uf.Box` Go types
backing images, are likewise unchanged — a `candy:` node routes to `uf.Box`
(image) or `uf.Candy` (layer) by the presence of `base:`/`from:`.

## The `charly box` Command Family

| Subcommand | Purpose | Skill |
|---|---|---|
| `charly box build` | Build container images from charly.yml | `/charly-build:build` |
| `charly box generate` | Write `.build/` Containerfiles | `/charly-build:generate` |
| `charly box inspect` | Print resolved image config as JSON | `/charly-build:inspect` |
| `charly box list {boxes,candies,targets,services,routes,volumes,aliases}` | List components from charly.yml | `/charly-build:list` |
| `charly box merge` | Merge small layers in a built image | `/charly-build:merge` |
| `charly box new candy <name>` | Scaffold a new candy directory | `/charly-build:new` |
| `charly box pull` | Fetch an image into local storage | `/charly-build:pull` |
| `charly check box` | Run declarative tests against a disposable container from a built image (reads the baked plan from the `ai.opencharly.description` OCI label) | `/charly-check:check` |
| `charly box validate` | Check charly.yml + layers | `/charly-build:validate` |

## Scope Boundary (Build vs. Deploy)

| | Reads `charly.yml` | Reads OCI labels | Reads `charly.yml` |
|---|---|---|---|
| `charly box …` | **Yes** (required) | Rarely | No |
| Everything else | **No** | Yes (required for deploy-mode) | Yes (overlay) |

If a new command needs to resolve candy dependencies, box inheritance, or
registry tag configuration, it must live under `charly box`. Any command that
operates on a running container or deployed image must go through
`ExtractMetadata` (labels) + charly.yml — never `LoadConfig`.

When a deploy-mode command is run against an image that isn't in local
storage, `ExtractMetadata`/`EnsureImage` return `ErrImageNotLocal` and the
top-level error handler renders: *"image 'X' is not available locally. Run
'charly box pull X' to fetch it first."* See `/charly-build:pull` for the full sentinel
pattern.

## Project directory resolution

Every `charly box …` command resolves `charly.yml` (and `candy/`, imported files, etc.) **relative to the current working directory** — internally via `os.Getwd()` on every entry point. Five ways to override that default — three local, two remote:

```bash
# Local project — pick a directory on disk:
charly -C /path/to/opencharly box list boxes          # short flag
charly --dir /path/to/opencharly box list boxes       # long flag
CHARLY_PROJECT_DIR=/path/to/opencharly charly box list boxes   # env var

# Remote project — clone (or hit cache) and chdir into it:
charly --repo opencharly/charly box list boxes        # bare owner/repo → github.com/owner/repo@<default-branch>
charly --repo opencharly/charly@main box list boxes   # pinned ref
charly --repo default box list boxes                      # literal "default" → opencharly/charly
CHARLY_PROJECT_REPO=opencharly/charly charly box list boxes
```

`--repo` and `--dir` are mutually exclusive (passing both exits with `charly: --repo and --dir are mutually exclusive`). All five paths are declared on the top-level `CLI` struct in `charly/main.go` and resolved by a single `os.Chdir(cli.Dir)` call **before** Kong dispatches the subcommand, so every existing `os.Getwd()` site picks up the new cwd — no per-command plumbing needed.

**Repo spec normalization** (in `charly/main_repo.go`):

- `default` → `github.com/opencharly/charly` at the default branch
- bare `owner/repo` → `github.com/owner/repo` (auto-prefix when first segment has no dot)
- bare `owner/repo@ref` → pinned to `ref`
- `host.tld/owner/repo[@ref]` → used literally (the dot in the host disambiguates)

Remote repos are cloned into `~/.cache/charly/repos/<repoPath>@<version>/` (override via `CHARLY_REPO_CACHE`). The cache is shared with the existing remote-layer fetcher (`charly/refs.go`, `charly/refs_git.go`) — both go through `EnsureRepoDownloaded`.

**Canonical use case**: running `charly mcp serve` inside a container. The container's cwd is `/workspace` (set by the `charly-mcp` layer's env + volume declaration). There are three deployment patterns, in order of progressively less local setup:

1. **Bind-mount** — the canonical `charly-mcp` pattern. Host project bind-mounted to the container's `/workspace`; volume NAME stays `project` for a stable deployer API. Use this when you want the agent to read your in-flight local edits.

   ```bash
   charly config charly-arch --bind project=/home/you/opencharly
   charly start charly-arch
   charly check live charly-arch --filter mcp   # the baked mcp: call box.list.boxes step
   ```

2. **Remote pin** — set `CHARLY_PROJECT_REPO=opencharly/charly@<sha-or-ref>` in the container env. The agent reads from a pinned upstream version. No bind mount required.

3. **Auto-default** — `charly mcp serve` with no `charly.yml` reachable at cwd silently falls back to `github.com/opencharly/charly`. The fallback fires whenever cwd lacks `charly.yml`, regardless of whether `CHARLY_PROJECT_DIR` is set (the `charly-mcp` layer permanently sets `CHARLY_PROJECT_DIR=/workspace`, so a fallback gated on the env var being empty would never fire). Pass `--no-default-repo` on the serve command to opt out. Only `charly mcp serve` auto-fetches; the top-level CLI stays opt-in.

The error messages are explicit when misconfigured: `cannot chdir to --dir "/missing": no such file or directory`. See `/charly-build:charly-mcp-cmd` "Deployment: the `charly-mcp` layer" for the full bind-mount pattern and `/charly-internals:go` "main.go" for the implementation note (guarded by `TestCharlyDir_FlagChdir` + `TestCharlyDir_Errors` in `main_dir_test.go`, and `TestNormalizeRepoSpec` + `TestCharlyRepo_*` in `main_repo_test.go`).

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| List boxes | `charly box list boxes` | Boxes from charly.yml |
| List build targets | `charly box list targets` | Build targets in dependency order (includes auto-intermediates) |
| Inspect image | `charly box inspect <image>` | Print resolved config as JSON |
| Inspect field | `charly box inspect <image> --format <field>` | Print single field (tag, base, layers, ports, etc.) |
| Validate | `charly box validate` | Check charly.yml + layers |
| Pull into local storage | `charly box pull <image>` | Fetch from registry so deploy-mode commands work |
| Run build-time tests | `charly check box <image>` | Runs the baked `check:` steps in a disposable `podman run --rm` container (`context: [build]` steps only). For full-stack live check against a running deployment, use `charly check live <name>`. See `/charly-check:check`. |
| Pre-prime remote repo cache | `charly box fetch [<spec>]` | Clones (or hits cache) for the spec — defaults to `default` (opencharly/charly). Prints the cache path. |
| Force re-clone | `charly box refresh [<spec>]` | Removes the cache entry and re-clones. |

### Authoring (the MCP-first surface)

Each verb below is also auto-exposed as an MCP tool (`box.new.project`, `box.new.box`, `box.set`, `box.add-candy`, `box.rm-candy`, `box.write`, `box.cat`, `candy.set`, `candy.add-rpm`, …) via `charly/mcp_server.go`'s Kong reflection. So an LLM agent driving `charly mcp serve` can author a project from scratch over RPC.

| Action | Command |
|--------|---------|
| Scaffold a fresh project | `charly box new project <dir>` |
| Add a box entry | `charly box new box <name> --base <ref> --layers <a,b,c>` |
| Add a candy dir (stub `charly.yml`) | `charly box new candy <name>` |
| Edit a value in `charly.yml` | `charly box set <dotpath> <yaml-value>` |
| Append a candy to a box | `charly box add-candy <image> <layer>` |
| Remove a candy from a box | `charly box rm-candy <image> <layer>` |
| Edit a value in `candy/<name>/charly.yml` | `charly candy set <name> <dotpath> <yaml-value>` |
| Append rpm/deb/pac/aur packages to a candy | `charly candy add-rpm <name> <pkg…>` (and `add-deb`, `add-pac`, `add-aur`) |
| Write any file under the project root | `charly box write <rel-path> [--content X \| --from-stdin]` |
| Read any file under the project root | `charly box cat <rel-path>` |

**Safety boundary**: `charly box write` / `charly box cat` resolve the path against `os.Getwd()` (the project root) and reject absolute paths or `..` traversal that would escape the root. They are the deliberate escape hatch for free-form auxiliary files (`pixi.toml`, `package.json`, `root.yml`, `*.service`, scripts) that the schema-aware setters don't cover.

**Comment preservation**: every YAML edit (`set`, `add-layer`, `rm-layer`, `add-rpm`, etc.) goes through the `yaml.v3` *node* API rather than the value API, so human-authored comments and key order are preserved across edits. Tested in `sdk/kit/yaml_test.go` and `charly/scaffold_project_test.go`.

**Project scaffold contents**: `charly box new project` writes a minimal `charly.yml` with `discover: [box, candy]` + empty `box/`/`candy/` dirs. The default distro/builder/init/resource build vocabulary (and the default sidecar templates) are EMBEDDED in the `charly` binary (`charly/charly.yml`, `//go:embed` — the single embedded default config, plain node-form YAML parsed by the same unified loader as any project `charly.yml`), so a new project is immediately usable with no build vocabulary to copy; declare `distro:`/`builder:`/`init:`/`resource:`/`sidecar:` (inline in `charly.yml` or an imported vocab file) only to extend or override the embedded default.

## charly.yml Structure

```yaml
defaults:
  registry: ghcr.io/opencharly
  tag: auto                    # CalVer: YYYY.DDD.HHMM
  platforms:
    - linux/amd64
    - linux/arm64
  build: [rpm]
  builder:                     # build type → builder image
    pixi: fedora-builder
    npm: fedora-builder
    cargo: fedora-builder
  merge:
    auto: false
    max_mb: 128

# Every image is a name-first node: the `candy:` discriminator (an image carries `base:`/`from:`) holds the scalar +
# build-vocabulary fields (base / version / builder / builds / platforms /
# build / description); every non-scalar collection (distro identity tags,
# candy composition, env, security) becomes its own `<box>-<key>:` child node.
fedora:
  candy:
    base: "quay.io/fedora/fedora:43"
  fedora-distro:
    distro: ["fedora:43", fedora]

fedora-builder:
  candy:
    base: fedora
    builds: [pixi, npm, cargo]  # declares what this builder can build
  fedora-builder-candy:
    candy:
      - pixi
      - nodejs
      - build-toolchain

my-app:
  candy:
    base: fedora
    env_file: "~/.config/my-app/.env"
  my-app-candy:
    candy:
      - supervisord
      - traefik
      - my-service          # published ports are inherited from the candies (no box `port:`)
  my-app-env:
    env:
      - MY_VAR=value
  my-app-security:
    security:
      cap_add: [SYS_PTRACE]
```

## Inheritance Chain

Every setting resolves through: **image -> defaults -> hardcoded fallback** (first non-null wins).

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `true` | Set `false` to disable (skipped by generate, validate, list) |
| `version` | `""` | OPTIONAL dedicated CalVer (`YYYY.DDD.HHMM`). When set it IS the image's `ai.opencharly.version` label; when unset the label is derived as the highest layer version across the chain (`EffectiveVersion`, `charly/effective_version.go`). Layered images leave it unset (they derive — keeps the label content-stable); a layerless bare base on an EXTERNAL registry base needs it (else the label can't be derived) — `charly migrate` backfills those |
| `status` | `""` (= `testing`) | `working`, `testing`, or `broken`. Effective status = worst of image + all layers |
| `info` | `""` | Free-form description. Aggregated with layer-level info in OCI labels |
| `base` | `quay.io/fedora/fedora:43` | External OCI image or name of another box |
| `bootc` | `false` | Adds `bootc container lint`, enables disk image builds |
| `platforms` | `["linux/amd64", "linux/arm64"]` | Target architectures |
| `tag` | `"auto"` | Image tag. `"auto"` for CalVer |
| `registry` | `""` | Container registry prefix |
| `distro` | `[]` | Distro identity tags in priority order: `["fedora:43", fedora]`. For packages: first matching section wins (override). For plan steps: additive. Inherited from base image |
| `build` | `["rpm"]` | Package formats tied to builder definitions: `[rpm]` or `[pac, aur]`. ALL formats installed in order. Valid: rpm, deb, pac, aur. Inherited from base image |
| `layers` | (required) | Layer list (image-specific, not inherited) |
| `user` | `"user"` | Username for non-root operations. See `user_policy:` — may be overridden at resolve time when adopt mode fires |
| `uid` | `1000` | User ID (may be overridden by `base_user:` under adopt) |
| `gid` | `1000` | Group ID (may be overridden by `base_user:` under adopt) |
| `user_policy` | `"auto"` | How to reconcile `user:` against the base image's pre-existing uid-1000 account. Values: `auto` / `adopt` / `create`. See "user_policy" section below |
| `merge` | `null` | Layer merge settings |
| `aliases` | `[]` | Command aliases |
| `builder` | `{}` | Build type → builder image map (inherited from base image + defaults). Keys match the embedded `builder:` vocabulary — e.g., `builder.pixi` selects which image to use as the pixi builder |
| `builds` | `[]` | What this builder image can build: `pixi`, `npm`, `cargo`, `aur` (not inherited) |
| `env` | `[]` | Runtime env vars (`KEY=VALUE`). Not inherited from defaults |
| `env_file` | `""` | Path to `.env` file for runtime injection. Not inherited |
| `security` | `null` | Container security options. Overrides layer-level security |
| `network` | `string` | Container network mode (default: shared `charly` network; set `host` for host networking) |

VM-related fields (`vm`, `libvirt`) are not valid on `candy:` image entries — the loader rejects them. VMs are declared as `kind: vm` entities in `vm.yml` — see `/charly-vm:vms-catalog` for authoring and `/charly-build:migrate` for `charly migrate` conversion of legacy configs. `bootc: true` stays on a `candy:` image entry (marks the image as a bootable container); a separate `kind: vm` entity with `source.kind: bootc` references it.

## Builder and Builds

Builder images provide build tools (pixi, npm, cargo, yay) for multi-stage builds without bloating final images. Three fields control this:

- **`builder:`** on images — map of build type → builder image name. Inherited: image → base image → defaults → `{}`. The keys (`pixi`, `npm`, `cargo`, `aur`) match entries in the embedded `builder:` vocabulary — intentionally the same word, because both maps key on the same slot.
- **`produce:`** on builder images — list declaring what the builder can build. Not inherited.
- **`build:`** — package formats tied to builder definitions (`rpm`, `deb`, `pac`, `aur`). ALL formats installed in order. Inherited from base image. Default: `[rpm]`.
- **`distro:`** — distro identity tags in priority order (`["fedora:43", fedora]`). First matching section overrides packages. Inherited from base image.

```yaml
defaults:
  builder:
    pixi: fedora-builder
    npm: fedora-builder
    cargo: fedora-builder

fedora-builder:
  candy:
    base: fedora
    builds: [pixi, npm, cargo]
  fedora-builder-candy:
    candy: [pixi, nodejs, build-toolchain]

arch:
  candy:
    base: "quay.io/archlinux/archlinux:base-20260525.0.535911"
    build: [pac]
    builder:
      pixi: arch-builder
      npm: arch-builder
      cargo: arch-builder
      aur: arch-builder
  arch-distro:
    distro: [arch]

arch-builder:
  candy:
    base: arch              # inherits build: [pac] AND builder: from arch
    builds: [pixi, npm, cargo, aur]
  arch-builder-candy:
    candy: [pixi, nodejs, build-toolchain, yay]

arch-test:
  candy:
    base: arch              # inherits builder: from arch
    build: [pac, aur]            # override to add aur format
  arch-test-candy:
    candy: [arch-pac-test, arch-aur-test]
```

Each build type resolves its builder independently: **`box.builder[type]` → `base_box.builder[type]` → `defaults.builder[type]` → `""`**. This means you can use `fedora-builder` for pixi but `arch-builder` for npm on the same image.

Self-reference protection: after merging defaults/base, any `builder` entry pointing to the image itself is filtered out. Builder images can't use themselves as builders.

Validation checks that every builder referenced in `builder:` declares the matching capability in `produce:`.

Source: `charly/generate.go` (`builderRefForFormat`), `charly/graph.go` (`ResolveBoxOrder`, `BoxNeedsBuilder`), `charly/validate.go` (`validateBuilders`).

## Internal Base Images

When `base` references another image in `charly.yml`, the generator resolves it to the full registry/tag and creates a build dependency. The referenced image must be built first.

```yaml
fedora:
  candy:
    base: "quay.io/fedora/fedora:43"

my-app:
  candy:
    base: fedora        # References fedora image above
  my-app-candy:
    candy: [my-layer]
```

## user_policy: adopt vs create

`user_policy:` cleanly handles base images that ship a pre-existing uid-1000 account (notably Ubuntu 24.04's `ubuntu:ubuntu`). A plain `getent passwd $UID || useradd …` bootstrap short-circuits on such accounts, leaving the image's configured `user:` never created — sudoers, `${HOME}`, npm prefix, etc. would then break because they assume the configured name exists.

The mechanism: a **declarative** fact (what the base image ships, in the embedded `distro.<name>.base_user:` vocabulary — see `/charly-build:build`) + an **image-level policy** (how to reconcile with the image's `user:` field).

### Policy values

| Policy | Behavior | Failure mode |
|--------|----------|--------------|
| `auto` (default) | If `base_user:` is declared for the image's distro AND the image didn't explicitly set `user:`, adopt the base_user. Otherwise create the configured user. | Never fails — falls through gracefully. |
| `adopt` | Always adopt. Error if the distro has no `base_user:` declaration. | Hard error at config resolve time. Use when you specifically need to lock adopt semantics. |
| `create` | Always create the configured user. | Build fails if `useradd` collides (should never happen on a "create" distro). |

### Decision matrix per base image

| Base image | `base_user` declared? | `user_policy: auto` outcome | Resolved user |
|---|---|---|---|
| `/charly-distros:fedora` | no | create | `user` |
| `/charly-distros:arch` | no | create | `user` |
| `/charly-distros:debian` | no | create | `user` |
| `/charly-distros:ubuntu` | **yes** (`ubuntu:1000:/home/ubuntu`) | adopt | `ubuntu` |

This is why `ubuntu-coder`'s resolved identity is `ubuntu:/home/ubuntu` while the other three coder images are `user:/home/user`. The charly.yml for all four coder images is identical on the user-related fields (no explicit `user:`); the policy + base_user together decide the outcome.

### How resolution flows (`charly/config.go ResolveBox`)

1. Resolve `User`, `UID`, `GID` from defaults → image overrides → hardcoded fallback `user` / `1000` / `1000`.
2. Load the distro config (`DistroConfig` from the embedded build vocabulary), resolve the image's `DistroDef` by walking `distro:` tags.
3. Apply `user_policy`:
   - `adopt` → overwrite User/UID/GID/Home with the distro's `BaseUser`, set `ResolvedBox.UserAdopted = true`.
   - `auto` → same overwrite IF `base_user` exists AND the image didn't explicitly set `user:`.
   - `create` → no-op.
4. `writeBootstrap` (`charly/generate.go`) keys on `UserAdopted`: adopt emits only a comment; create emits an idempotent `useradd` (see `/charly-build:generate`).

### Live verification

```bash
charly box inspect ubuntu-coder | grep -E '"User"|"UID"|"Home"|UserAdopted'
# "User": "ubuntu",
# "UID": 1000,
# "Home": "/home/ubuntu",
# "UserAdopted": true,

charly box inspect debian-coder | grep -E '"User"|"UID"|"Home"|UserAdopted'
# "User": "user",
# "UID": 1000,
# "Home": "/home/user",
# "UserAdopted": false,
```

### Layer consequences

Adopt mode means `resolved.User` is not a stable string across distros. Layers that reference the uid-1000 account by name must NOT hardcode `user` — use `${USER}` where the generator substitutes (step fields like `run_as: ${USER}`), or use `getent passwd 1000 | cut -d: -f1` inside `command:` blocks (where the generator does NOT substitute — bash sees the script verbatim). The canonical getent example is `/charly-coder:sshd`'s sudoers step.

See also `/charly-distros:ubuntu` (canonical adopt consumer), `/charly-build:build` "base_user:", `/charly-internals:go` "ResolvedBox.UserAdopted".

## External Bases Require Explicit `distro:`

When `base` is a URL string (not the name of another image in `charly.yml`), the generator treats it as **external** and does not inherit distro tags or build formats. This is the canonical gotcha for bootc images, which typically use `quay.io/fedora/fedora-bootc:43`:

```yaml
# ❌ BROKEN — no `<box>-distro:` child node → Distro resolves to null, no RPM installs emitted
my-bootc-image:
  candy:
    base: "quay.io/fedora/fedora-bootc:43"
    bootc: true
  my-bootc-image-candy:
    candy: [sshd, qemu-guest-agent, ffmpeg]

# ✓ CORRECT — explicit distro: tags matching the base, in a `<box>-distro:` child node
my-bootc-image:
  candy:
    base: "quay.io/fedora/fedora-bootc:43"
    bootc: true
  my-bootc-image-distro:
    distro: ["fedora:43", fedora]
  my-bootc-image-candy:
    candy: [sshd, qemu-guest-agent, ffmpeg]
```

Symptom without `distro:`: `charly box inspect <image>` shows `"Distro": null`. The generator's install_template Phase-2 branch short-circuits on `img.DistroDef == nil`, so **no layer `rpm:` install RUN steps are emitted**. The image builds cleanly but is missing every package from every layer that uses declarative `rpm:` sections. Explicit `command: dnf install …` steps still run; the bug affects only declarative `rpm:`/`deb:`/`pac:` sections.

Internal bases (`base: fedora`) inherit `distro:` and `build:` from the parent image automatically — you only need explicit tags on images whose `base:` is a URL. The `quay.io/fedora/fedora-bootc:43` example above is the canonical pattern: an external bootc base must declare its own `distro:` tags, or the generator sees `Distro: null` and emits no rpm-install RUN steps.

## Intermediate Images

When multiple images share the same base and common layer prefixes, `charly` auto-generates intermediate images at branch points to maximize cache reuse.

```
fedora (external)
  -> fedora-supervisord (auto: pixi + python + supervisord)
     -> fedora-test (adds: traefik, testapi)
     -> openclaw (adds: nodejs, openclaw)
```

Auto-intermediates are marked with `Auto: true` and appear in `charly box list targets`.

### Algorithm

`ComputeIntermediates()` runs during generation:
1. `GlobalCandyOrder()` computes a deterministic layer ordering across all images, prioritizing layers by popularity (how many images need them) for cache efficiency.
2. Images are grouped by their direct parent (base). For each sibling group with 2+ images, a **prefix trie** is built from their relative layer sequences.
3. The trie is walked to detect branch points (where sibling layer sequences diverge). At each branch, an auto-intermediate image is created.
4. Original images are rebased to the nearest intermediate, so shared layers are built once.

Source: `charly/intermediates.go` (`ComputeIntermediates`, `GlobalCandyOrder`, `walkTrieScoped`).

## Versioning

CalVer: `YYYY.DDD.HHMM` (year, day-of-year, UTC time). Computed once per `charly box generate`.

| `tag` value | Generated tag(s) |
|-------------|-----------------|
| `"auto"` | `YYYY.DDD.HHMM` + `latest` |
| `"nightly"` | `nightly` only |
| `"1.2.3"` | `1.2.3` only |

Override: `charly box generate --tag <value>`.

## Runtime Environment Variables

The `env` and `env_file` fields inject environment variables into containers at runtime (not build time):

```yaml
my-app:
  candy:
    env_file: "~/.config/my-app/.env"
  my-app-env:
    env:
      - DB_HOST=localhost
      - LOG_LEVEL=info
```

These are the lowest priority in the env resolution chain. CLI flags (`-e`, `--env-file`) and workspace `.env` take precedence. See `/charly-core:charly-config` and `/charly-core:start` for the full priority chain at config-time and run-time respectively.

Source: `charly/envfile.go` (`ResolveEnvVars`).

## Security Configuration

Box-level `security:` overrides candy-level security settings:

```yaml
my-app:
  candy:
    base: fedora
  my-app-security:
    security:
      privileged: true
      cap_add: [SYS_ADMIN]
      devices: [/dev/fuse]
      security_opt: [label:disable]
```

Box `security.privileged` replaces the candy-derived value. `cap_add`, `devices`, `security_opt` are appended to candy-collected values (deduplicated). Applied as container run arguments at runtime (not build time).

Source: `charly/security.go` (`CollectSecurity`).

## VM Configuration

VMs are **not** configured on `candy:` image entries. The `vm:` and `libvirt:` fields on a `candy:` image are rejected at load time. VM primitives are declared as `kind: vm` entities in `vm.yml`:

```yaml
# vm.yml (any file — the loader routes by shape, not filename)
my-bootc-vm:
  vm:
    source:
      kind: bootc
      box: my-bootc-image        # `box:` source field → the `candy:` image node above (must have bootc: true)
    disk_size: 10 GiB
    ram: 4G
    cpus: 2
  my-bootc-vm-libvirt:
    libvirt:
      devices:
        filesystems: [{type: mount, source: ..., target: ...}]
```

See `/charly-vm:vms-catalog` for the full VmSpec schema, `/charly-vm:vm` for the `charly vm build/create/ssh` command family, and `/charly-build:migrate` for `charly migrate` to convert legacy `box.vm:` / `box.libvirt:` fields to the new schema.

## Ports — inherited from candies, auto-allocated at deploy

**Boxes do NOT declare ports.** A box's published ports are inherited from EVERY candy in its base chain — the candy that runs a service declares the container port (the candy's `<name>-port:` child node), and `CollectBoxPorts` (`charly/ports.go`, over the shared `boxCandyChain` walk) collects the full set. The same set feeds both the `ai.opencharly.port` OCI label and the Containerfile `EXPOSE` directives, so they can never diverge. A residual box-level `port:` is a hard load error pointing at `charly migrate`.

```bash
charly box inspect android-emulator --format ports
# 2222   (sshd)         3000  (selkies)      4723 (appium-server)
# 5037   (android adb)  9222  (chrome-cdp)   9224 (chrome-devtools-mcp)
# — all inherited from the candy chain; the box declares no `port:`
```

**Host mappings are auto-allocated on `127.0.0.1` at deploy.** At `charly config`, every inherited container port without an explicit deploy pin gets a freshly-allocated free loopback host port (`ResolveDeployPorts`), persisted as `resolved_port:` and stable across `charly update`. A deploy/bed `port:` entry is a PIN (`host:container`) for specific container ports — the rest still auto-allocate. `charly status` shows the live mapping; check probes resolve it via `${HOST_PORT:N}`. See `/charly-core:deploy` and `/charly-check:check`.

## OCI Labels

Every image `charly` builds carries a set of `ai.opencharly.*` OCI labels embedding the resolved image config so that `charly config` and `charly bundle` can work without the project source tree. The full list is assembled in `charly/labels.go`:

| Label | Contents |
|---|---|
| `ai.opencharly.volume` | Volume declarations from the layer chain |
| `ai.opencharly.port` | Published container ports, **inherited from the candy chain** (`CollectBoxPorts`) — bare container ports; host mappings are auto-allocated at deploy |
| `ai.opencharly.security` | `cap_add`, `devices`, `security_opt`, `mounts`, resource caps |
| `ai.opencharly.env` | Runtime env keys |
| `ai.opencharly.env_provide` | Cross-container env provides (resolved at deploy time) |
| `ai.opencharly.env_require` | Declared env contracts (used for `charly config` hard-fail checks) |
| `ai.opencharly.env_accept` | Opt-in allowlist for provides filtering |
| `ai.opencharly.mcp_provide` | Cross-container MCP server provides |
| `ai.opencharly.port_proto` | Port protocol annotations (non-default only) |
| `ai.opencharly.platform.distro` | Distro identity (e.g. `["arch"]`) — first match picks bootstrap/format templates |
| `ai.opencharly.platform.format` | Package formats installed (`pac`, `rpm`, `deb`, `pixi`, `aur`, …) |
| `ai.opencharly.builder.use` | Consumer-side routing map: format → builder-image name |
| `ai.opencharly.builder.provide` | Producer-side capability list: formats this image can build for others |

All of the above round-trip via `charly config`: the label is read from the image manifest and applied to charly.yml + the quadlet. There is one deliberate exception.

### Tunnel is charly.yml-only

`labels.go:334` **explicitly skips reading** any tunnel label when resolving an image's deploy config. Tunnels (Tailscale serve, Cloudflare tunnel) are treated as a **deployment** decision, not an image attribute — they live exclusively in `charly.yml`. This was the deliberate design of commit `2759124` (tunnel→charly.yml migration), motivated by three concerns:

1. **Per-instance divergence.** One selkies-desktop image may be deployed with a Tailscale tunnel in one environment and no tunnel in another. Baking the tunnel choice into the image forecloses that.
2. **`--update-all` safety.** Propagating config changes across deployed services must not accidentally rewrite tunnel settings from image labels and blow away per-instance overrides.
3. **Instance inheritance gap.** Tunnel config is **not** auto-inherited from the base `charly config <image>` call to an `charly config <image> -i <instance>` call. This is a deliberate gap — see `/charly-selkies:selkies-labwc` (Multi-Instance Proxy Deployment) for the manual workaround and `/charly-core:deploy` (Instance Tunnel Inheritance) for the full lifecycle.

**Practical implication:** you can inspect an image's tunnel declaration with `charly box inspect <image>` and see nothing useful — that's correct. To see a tunnel's actual state, read `charly.yml` directly (`charly bundle show <image>`) or the generated quadlet (`charly status <image>`).

## Common Workflows

### Add a New Image

Add an entry to `charly.yml` with `base` and `layers`, then build:

```bash
# Edit charly.yml
# Then:
charly box build my-new-image
```

### Layer Images (inheritance)

Set `base` to another image name:

```yaml
nvidia:
  candy:
    base: fedora
    platforms: [linux/amd64]
  nvidia-candy:
    candy: [cuda]

ml-workstation:
  candy:
    base: nvidia
  ml-workstation-candy:
    candy: [python-ml, jupyter]
```

### Disable an Image

```yaml
experimental:
  candy:
    enabled: false
    base: fedora
  experimental-candy:
    candy: [experimental-layer]
```

## Cross-References

### Family subcommand skills

- `/charly-build:build` -- `charly box build` (+ the `--no-cache` intermediate scratch-stage caveat)
- `/charly-build:generate` -- `charly box generate` (Containerfile generation including OCI label emission)
- `/charly-build:inspect` -- `charly box inspect` (resolved OCI label set)
- `/charly-build:list` -- `charly box list {boxes,candies,targets,services,routes,volumes,aliases}`
- `/charly-build:merge` -- `charly box merge` (post-build layer consolidation)
- `/charly-build:new` -- `charly box new candy <name>` (scaffold new candy directory)
- `/charly-build:pull` -- `charly box pull` (fetch into local storage; `ErrImageNotLocal` recovery)
- `/charly-build:validate` -- `charly box validate` (charly.yml + candies consistency check)

### Related skills

- `/charly-image:layer` -- Candy definitions that compose into boxes (env_provide, env_require, env_accept, security resource caps)
- `/charly-core:deploy` -- Deploying built images (quadlet, bootc, tunnel lifecycle, instance tunnel inheritance)
- `/charly-core:charly-config` -- `charly config` reads OCI labels + charly.yml; tunnel is charly.yml-only
- `/charly-internals:go` -- `LoadConfig`, `ExtractMetadata`, `EnsureImage`, `ErrImageNotLocal` source locations
- `/charly-check:check` — Box-level plan steps (cross-candy invariants; deploy-default checks shipped with the image are `check:` steps carrying `context: [deploy]`). The plan steps are embedded in the `ai.opencharly.description` OCI label.
- `/charly-build:charly-mcp-cmd` — if the image transitively bundles an mcp-providing candy (e.g. `jupyter`, `chrome-devtools-mcp`), the bundled candy's `mcp:` tests run as part of `charly check live <image> --filter mcp`; see the skill for per-verb details and the port-publishing gotcha.
- `/charly-vm:vm` — `charly vm build/create/start/stop/ssh` command family; reads `vm.yml`, not `charly.yml`. Covers BIOS vs UEFI firmware, virtio-gpu video model, bootc caveats (rootful storage refresh, `-v /dev:/dev` loopback).
- `/charly-vm:vms-catalog` — authoring reference for the `kind: vm` entity schema.
- `/charly-build:migrate` — `charly migrate` converts legacy VM fields to `vm.yml`.

## Cross-kind name reuse

Every entity is a top-level **name-first** node, so within a single document the top-level node names are **globally unique**: a `candy` (image or layer), a `pod`, a `vm`, a `k8s`, and a `local` in ONE `charly.yml` MUST NOT share a name (they would collide on the same YAML key — `charly box validate` flags it; rename one, e.g. the convention of suffixing the template a deploy inherits). Cross-FILE name reuse across SEPARATE discovered files (a layer `candy/redis` + an image `box/redis` — both `candy:` nodes, routed to distinct internal maps `uf.Candy` vs `uf.Box` by `base:`/`from:` presence) IS still permitted, and verbs disambiguate by command context. Authoring verbs (`charly box set`, `charly box new box`, `charly box add-candy`, `charly box rm-candy`, `charly box new project`) write exclusively to `charly.yml` — a per-kind sibling file is reachable only via the `import:` statement from `charly.yml`, never as a default authoring target. Missing `charly.yml` → hard error pointing at `charly box new project .` or `charly migrate`. See CLAUDE.md "cross-FILE cross-kind reuse is fine, but a single document's top-level node names are GLOBALLY UNIQUE".

### Files are generic kind-containers (per-kind filenames are a convenience)

Every YAML file is a generic, kind-agnostic container — the loader routes each document by its top-level kind-key (its SHAPE), **NEVER by filename**. So ANY file may hold ANY mix of kinds. Splitting entities into per-kind sibling files named for their kind (`vm.yml` for VMs, `pod.yml` for pod deploys, …) is a pure user **CONVENIENCE** you express in `charly.yml`'s `import:` (and, for candy directories, `discover:`) — it is never required, and the code hardcodes no per-kind filename. **`charly.yml` is the only filename the code knows**; everything else (which files to `import:`, which directories + manifest names to `discover:`) is configured there. Inline maps in `charly.yml` and per-kind splits load identically. `discover:` is a flat generic scan-spec list (`- {path, recursive, manifest}`); the manifest defaults to `charly.yml` but is overridable per spec. Migration of legacy configs: `charly migrate` (idempotent). See `/charly-build:migrate`, `/charly-internals:go`.

The kind schemas each document is validated against (`box` / `candy` / `vm` / …) are **CUE-single-source**: the `@go()`-annotated `sdk/schema/*.cue` defs are the sole source for both the Go param structs (generated into `sdk/spec` by `task cue:gen`) and load-time validation, so changing a box/candy field is a CUE edit → `task cue:gen` → see the `/charly-internals:go` recipe "How to change the charly.yml schema (CUE is the single source of truth)".

## The `import:` statement (composition + namespaces)

`import:` is the **single** composition statement — a **list**, one statement per project. Each list item is one of two shapes:

| Shape | YAML | Semantics |
|---|---|---|
| **Flat** | a bare string — `- build.yml`, `- '@github.com/owner/repo/build.yml:vTAG'` | Merge the referenced file's entities into THIS project's root namespace (root-wins). Use for same-repo per-kind file splits AND an optional project-level `build.yml` that overrides or extends the embedded `distro`/`builder`/`init` vocabulary. |
| **Namespaced** | a single-key map — `- {cachyos: box/cachyos}`, `- {charly: ../..}`, `- {base: '@github.com/owner/repo:vTAG'}` | Mount another project as an isolated child namespace under `alias`; its entries are NOT flat-merged, they're referenced QUALIFIED as `alias.entry`. |

### Qualified refs (`ns.entry`)

A namespaced import is reached through a dotted ref everywhere a name is resolved — `base:`, `builder:` map values, deploy cross-refs:

```yaml
import:
  - build.yml                       # flat — optional build-vocabulary override
  - charly.yml                       # flat — this repo's own box nodes
  - cachyos: box/cachyos          # namespaced child import

versa:
  candy:
    base: cachyos.cachyos           # the `cachyos` image inside the `cachyos` namespace
```

Resolution is **namespace-relative**, exactly like Go package-member access: a bare ref inside a namespace resolves within that namespace first; a qualified ref descends one level per dot (`a.b.c` → namespace `a`, then `b`, then leaf `c`). The `arch` and `fedora` submodules are SELF-CONTAINED (`import: []`): their base/builder stacks are bare-local, so their images write `base: arch` / `base: fedora` and route builders to a bare-local `arch-builder` / `fedora-builder`. The `cachyos` submodule imports the **`opencharly/distro-arch`** submodule under the `arch` namespace, so it reaches the Arch base/builder as `arch.arch` / `arch.arch-builder`. The main repo, in turn, imports all three submodules (`arch` / `cachyos` / `fedora` namespaces) to reference their relocated boxes.

### Inheritance across a namespace boundary

- **`distro:` / `build:`** are VALUES (distro tags, package formats) → inherited across a namespace boundary, so a `base: cachyos.cachyos` image still picks up cachyos's `distro:`/`build:`.
- **`builder:`** is a map of REFS relative to the BASE's namespace → it does **NOT** cross the boundary. A consumer image that builds a multi-stage format declares its OWN `builder:` map, qualified to the right builder (e.g. the `cachyos` base, which imports the `arch` namespace, declares `builder: {pixi: arch.arch-builder}`). This avoids leaking a base-namespace-relative ref into a consumer where that namespace doesn't exist.

A repo reached via two import paths (e.g. `arch`, reached both directly as main → `arch` and transitively as main → `cachyos` → `arch`) — or an import cycle between two projects that import each other — is resolved to a single materialization at load time **by repo identity, not pinned version** — see `/charly-internals:go` "import-namespace loader". The consequence for authors: **the importing project's namespace pins win**. When an imported namespace's release imports your repo back (`<root>: @…:<someOldPin>`), that back-reference resolves to YOUR local working tree (the root), NOT the old pinned snapshot — so a stale transitive pin in a published submodule release can never drag a divergent (or stale-schema) version of your own repo into the load.

**`repo:` (optional root-only field).** Declare your project's canonical repo identity at the top of `charly.yml` (`repo: github.com/opencharly/charly`) so the loader recognizes a transitive back-import of your repo and short-circuits it to the local tree. When omitted, the loader infers it from `git remote origin`; absent both, the cycle-break degrades to version-keyed behavior. The field is purely additive (no migration needed).

### Candy-version resolution across namespaces — per-entity version

A namespace is imported to provide bases/builders; the resolver fetches ONLY the layers reachable from the enabled images' `base:`/`builder:` chains (reachability-scoped collection) — a namespace's unreferenced images and its `kind:local` templates are not pulled. The git `:vTAG` on a layer ref is only the FETCH coordinate; the layer's OWN `version:` (read after fetch) is the identity. So when the SAME layer is referenced via two different repo git tags but its `version:` is unchanged (a re-tag for an unrelated push), the resolver picks one materialization with NO warning. Only when a layer resolves to two genuinely different per-entity versions (a family pinned to a newer layer than the shared infra it composes) does it **warn once** (naming both per-entity versions) and use the **newest** (highest CalVer). Run `charly box reconcile` to align the on-disk git-tag pins and clear any warning. See `/charly-internals:go` "Remote-layer resolver", `/charly-build:reconcile`.

## Base stacks live in their distro submodules

The arch and fedora base-distro stacks are no longer carried by the main repo — each is owned by its `box/<distro>` submodule:

- **`box/arch`** owns `arch` + `arch-builder` (+ `cuda-arch-builder`), bare-local, and is SELF-CONTAINED (`import: []`).
- **`box/fedora`** owns `fedora` + `fedora-builder` + `fedora-nonfree` (+ the `nvidia` / `python-ml` GPU bases), bare-local, and is SELF-CONTAINED (`import: []`).
- **`box/cachyos`** owns the `cachyos` base (+ the pacstrap pair and the selkies GPU desktops) and imports the `arch` namespace to reach `arch.arch` / `arch.arch-builder` / `arch.cuda-arch-builder`.

The main repo imports all three submodules (`arch` / `cachyos` / `fedora` namespaces) to reference their relocated boxes from its own `check`/`vm`/`local`/`k8s`/`android` entities (one-directional — the submodules import nothing back from main). The distro/builder/init build vocabulary is embedded in the `charly` binary (no `build.yml` import). See `/charly-distros:arch`, `/charly-distros:fedora`, `/charly-distros:cachyos`.

## When to Use This Skill

**MUST be invoked** when the task involves box definitions in charly.yml, box inheritance, defaults, platforms, builder configuration, or the box dependency graph. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Pre-build. Define images before building. See also `/charly-image:layer` (candy authoring), `/charly-build:build` (building).

## Related skills

- `/charly-build:migrate` — `charly migrate` migrates legacy configs into the canonical single-`charly.yml` layout
- `/charly-internals:capabilities` — OCI label contract emitted at build time and consumed by deploy commands

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM in vm.yml.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See CLAUDE.md R1–R10.
