---
name: githubrunner
description: |
  Self-hosted GitHub Actions runner on CachyOS, fully rootless — runs as
  uid=1000 with zero added capabilities (no root, no privileged) via
  container-nesting, with rootless nested podman/buildah/skopeo for CI.
  Host networking retained for reachability. MUST be invoked before building,
  deploying, configuring, or troubleshooting the githubrunner box.
---

# githubrunner

Self-hosted GitHub Actions runner on **CachyOS**, fully rootless. Shares the
rootless nested-container posture with `/charly-openclaw:openclaw-desktop` (uid=1000,
no caps, `unmask=/proc/*` via `/charly-distros:container-nesting`).

## Box Properties

| Property | Value |
|----------|-------|
| Base | cachyos (`cachyos.cachyos`) |
| Layers | agent-forwarding, github-runner, charly, dbus, container-nesting |
| Build | pac |
| Platforms | linux/amd64 |
| UID / user | **1000 / user** (rootless — NO uid/privileged override) |
| Network | host (reach the host-side ghcr pull-through mirror) |
| Security | container-nesting's posture: `cap_add:[]`, `security_opt:[unmask=/proc/*]`, devices `/dev/fuse` + `/dev/net/tun` |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `cachyos` (`docker.io/cachyos/cachyos-v3`, via the `cachyos` import namespace)
2. `agent-forwarding` — GPG/SSH/direnv (composes gnupg + direnv + ssh-client)
3. `github-runner` — the Actions runner agent (under `${HOME}/actions-runner`),
   cosign, go/git/jq, qemu-user-static (aarch64 cross-arch CI), the .NET runtime
   deps, the credential-backed registration, the ghcr mirror config
4. `charly` — the charly binary + `virtualization` + `gocryptfs` + `socat`
5. `dbus` — session bus (for runner hooks)
6. `container-nesting` — rootless nested podman/buildah/skopeo + the subuid/subgid
   layout + newuidmap/newgidmap file-caps + containers/storage/policy configs

## Rootless posture (genuinely uid 1000, no caps)

The box carries **no uid/user/privileged override**, so it resolves to
`container-nesting`'s posture: uid=1000, `cap_add:[]`, `security_opt:[unmask=/proc/*]`,
devices `/dev/fuse` + `/dev/net/tun`. The runner process (`run.sh`), all CI jobs,
and rootless nested podman all run as `user` (uid 1000). See
`/charly-distros:container-nesting` for the `mount_too_revealing()` kernel RCA that
makes nested podman work without caps or `--privileged`.

`/charly-coder:sshd` (passwordless `/etc/sudoers.d/charly-user`) is composable if a
workflow genuinely needs sudo; it is not composed by default.

## Nested container support

`githubrunner` composes `/charly-distros:container-nesting` directly, so CI jobs get
first-class **rootless nested podman/buildah/skopeo** (uid 1000, `/dev/fuse` +
`unmask=/proc/*`, `crun` + `fuse-overlayfs`, `BUILDAH_ISOLATION=chroot`). The
rootless image cache lives under `${HOME}/.local/share/containers`. Cross-arch
container builds (aarch64) work via the repo `qemu-user-static` +
`qemu-user-static-binfmt` packages.

## CI: builds the org's release packages on itself

The repo's `release-packages` workflow (`.github/workflows/release-packages.yml`)
runs on this runner via `runs-on: [self-hosted, opencharly]` — no GitHub-hosted
runner. Because the runner is an Arch (CachyOS) host carrying the FULL `charly`
PKGBUILD `depends=` set, all three package formats build here:

- **pac** builds NATIVELY — `charly box pkg pac` → `makepkg -sf` as uid 1000 (makepkg
  refuses root; the rootless runner's non-root uid is exactly right). Every
  `depends=` is pre-installed, so makepkg resolves them without `sudo pacman` (the
  runner has no passwordless sudo). No `archlinux:latest` container.
- **rpm + deb** build distro-natively in the runner's rootless nested podman
  (`charly box pkg rpm deb`).

`workflow_dispatch` runs the build jobs from a branch (the release-upload step is
tag-guarded), so the build is exercisable without minting a tag. The `github-runner`
candy completes the `charly` runtime on the runner — beyond the .NET/runner deps it adds
the `depends=` packages the charly/virtualization candies don't already provide
(`slirp4netns`, `libisoburn`, `cdrtools`, `swtpm`).

## Token mechanism (credential-backed; obtained via `gh`)

`RUNNER_TOKEN` is a `secret_accept` (credential-store-backed — never written to
charly.yml or the quadlet); `RUNNER_ORG` is an `env_accept`. The registration
token is short-lived and only consumed once at `charly config` time (the registered
runner persists its own `.credentials` on the `state` volume), so it is obtained
fresh from `gh`. The `post_enable`/`pre_remove` hooks are guarded — they skip
when `RUNNER_TOKEN` is empty, so a token-less deploy (e.g. an check bed) brings the
image up without registering, and a stale token never errors a teardown.

```bash
# Obtain a fresh org registration token and register:
TOKEN=$(gh api -X POST /orgs/<org>/actions/runners/registration-token --jq .token)
charly config githubrunner -e RUNNER_ORG=<org> -e RUNNER_TOKEN="$TOKEN"   # token scrubbed → credential store
charly start githubrunner
```

Removal deregisters via the `pre_remove` hook, which needs a **remove**-token
(distinct from the registration token):

```bash
charly remove githubrunner -e RUNNER_TOKEN=$(gh api -X POST /orgs/<org>/actions/runners/remove-token --jq .token)
```

## Lifecycle

```bash
charly box build githubrunner
charly config githubrunner -e RUNNER_ORG=<org> -e RUNNER_TOKEN="$TOKEN"
charly start githubrunner
charly stop githubrunner
charly remove githubrunner -e RUNNER_TOKEN=<remove-token>
```

## Key Candies

- `/charly-distros:github-runner` — runner agent, hooks, registration, ghcr mirror, .NET deps + the charly-host `depends=` completion (native pac builds in CI)
- `/charly-distros:container-nesting` — rootless nested podman/buildah/skopeo, subuid layout, caps
- `/charly-tools:charly` — the charly binary + virtualization + gocryptfs + socat
- `/charly-distros:agent-forwarding` — GPG/SSH/direnv for the `.secrets` workflow

## Related Boxes

- `/charly-distros:cachyos` — the CachyOS base (parent, via the `cachyos` namespace)
- `/charly-openclaw:openclaw-desktop` — same rootless container-nesting posture (uid 1000, no caps)
- `/charly-distros:charly-fedora`, `/charly-coder:charly-arch` — the charly-toolchain siblings (root path, box-level full-hammer security)

## Related Commands

- `/charly-core:charly-config` — deploy setup with RUNNER_ORG (env) / RUNNER_TOKEN (secret)
- `/charly-core:start`, `/charly-core:stop`, `/charly-core:remove` — lifecycle + pre-remove deregistration
- `/charly-core:charly-status`, `/charly-core:logs` — verify runner is idle + troubleshoot
- `/charly-build:secrets` — the credential store backing `RUNNER_TOKEN`

## Verification

Build-scope (`charly check box githubrunner`) + deploy-scope (`charly check live`) checks
ship on the `github-runner` candy (functional: `config.sh --version` proves the
.NET deps resolved; rootless nested `podman run` proves the posture). The
disposable R10 bed is **`check-githubrunner-pod`** (`charly check run check-githubrunner-pod`)
— it proves the rootless composition WITHOUT GitHub registration (no token →
guarded hooks no-op).

After `charly start` against a registered deploy:

- `charly status githubrunner` — container running
- `charly shell githubrunner -c "id"` — uid=1000(user) (rootless)
- `charly shell githubrunner -c "podman run --rm quay.io/libpod/alpine:latest true"` — rootless nested podman works
- Runner appears as "Idle" in the org's Settings > Actions > Runners

## When to Use This Skill

**MUST be invoked** when the task involves the githubrunner box,
self-hosted runners, or GitHub Actions CI/CD. Invoke this skill BEFORE
reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
- `/charly-check:check` — the `check:` checks + the `check-githubrunner-pod` R10 bed
