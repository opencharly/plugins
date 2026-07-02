---
name: github-runner
description: |
  GitHub Actions self-hosted runner as a supervised container service — rootless
  (uid 1000), Arch/CachyOS packages, credential-backed registration token.
  Use when working with GitHub Actions runners, CI/CD infrastructure, or runner registration.
---

# github-runner -- GitHub Actions self-hosted runner

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord`, `container-nesting` |
| Volume | `state` -> `${HOME}/actions-runner` |
| Service | `github-runner` (supervisord; runs `run.sh` as uid 1000) |
| Security | none of its own — rootless nested podman comes from `container-nesting` (no `privileged`) |
| Install files | `task:` — declarative pinned `download:` of the runner tarball + `write:` of the ghcr mirror config; the runner tree is root-extracted (the shared download cache is root-owned) then `chown -R`ed to uid 1000 (the one ownership `cmd:`) |

## Packages (`distro.arch`, all in the official core/extra repos)

- Toolchain: `jq`, `git`, `go`, `cloud-guest-utils`, `cosign`
- Cross-arch CI: `qemu-user-static`, `qemu-user-static-binfmt` (aarch64 binfmt)
- .NET runtime deps for the runner binary (its `installdependencies.sh` has no
  Arch branch): `icu`, `krb5`, `openssl`, `libunwind`, `lttng-ust` (NOT `zlib` —
  CachyOS ships `zlib-ng-compat`, which Provides it; an explicit `zlib` conflicts)
- charly-host `depends=` completion: `slirp4netns`, `libisoburn`, `cdrtools`, `swtpm`
  — the part of the `charly` PKGBUILD `depends=` set the charly/virtualization candies do
  not already install. With these present, `charly box pkg pac` builds the pac release
  artifact NATIVELY on the runner (`makepkg -sf` resolves every dep and never
  shells out to `sudo pacman`). See `/charly-distros:githubrunner` "CI: builds the
  org's release packages on itself".

`podman`/`buildah`/`skopeo`/`crun`/`fuse-overlayfs` are provided by the
`container-nesting` dependency (not redeclared here — R3).

## Environment / token contract

| Variable | Mechanism |
|----------|-----------|
| `RUNNER_ORG` | `env_accept` (plaintext identifier; supplied at deploy) |
| `RUNNER_TOKEN` | `secret_accept` (credential-store-backed; never in charly.yml/quadlet) |
| `RUNNER_WORK_DIR` | `${HOME}/actions-runner/_work` |
| `RUNNER_GROUP` | `Default` |

The runner installs under `${HOME}/actions-runner` and runs as uid 1000. The
ghcr.io pull-through mirror (`127.0.0.1:5000`) config is written to the user
location `${HOME}/.config/containers/registries.conf.d/` (rootless podman).

## Lifecycle Hooks (token-guarded)

- **post_enable** — registers the runner with `RUNNER_ORG` + `RUNNER_TOKEN`.
  Skips (no-op) when `RUNNER_TOKEN` is empty — so a token-less deploy (an check
  bed) brings the image up without registering.
- **pre_remove** — deregisters; needs a **remove**-token (distinct from the
  registration token). Also skips when the token is empty.

## Usage

```yaml
# charly.yml — rootless, CachyOS
githubrunner:
  base: cachyos.cachyos
  build: [pac]
  candy: [agent-forwarding, github-runner, charly, dbus, container-nesting]
  network: host          # no uid/privileged override → rootless
```

```bash
TOKEN=$(gh api -X POST /orgs/myorg/actions/runners/registration-token --jq .token)
charly config githubrunner -e RUNNER_ORG=myorg -e RUNNER_TOKEN="$TOKEN"
charly remove githubrunner -e RUNNER_TOKEN=$(gh api -X POST /orgs/myorg/actions/runners/remove-token --jq .token)
```

## Used In Boxes

- `/charly-distros:githubrunner`

## Related Candies

- `/charly-infrastructure:supervisord` — process manager dependency
- `/charly-distros:container-nesting` — rootless nested podman/buildah/skopeo + subuid layout + caps

## When to Use This Skill

Use when the user asks about:

- GitHub Actions self-hosted runners
- Runner registration or deregistration
- CI/CD container infrastructure
- `RUNNER_TOKEN` or `RUNNER_ORG` configuration

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, secret_accept, check block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block + the `check-githubrunner-pod` bed
- `/charly-build:secrets` — the credential store backing `RUNNER_TOKEN`
