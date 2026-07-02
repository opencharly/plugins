---
name: ubuntu-builder
description: |
  Minimal Ubuntu 24.04 builder image (pixi + Node.js + build-toolchain)
  used as the multi-stage builder for Ubuntu-based boxes — currently
  ubuntu-coder. Runs as uid 1000 `ubuntu` (adopted from the upstream
  ubuntu:24.04 base image via the embedded distro vocabulary's base_user declaration).
  MUST be invoked before building, deploying, configuring, or troubleshooting
  the ubuntu-builder box.
---

# ubuntu-builder

Ubuntu 24.04 (noble) counterpart of `/charly-distros:fedora-builder` and `/charly-distros:debian-builder`. Same role — pixi/npm/cargo multi-stage builder — with one important difference: the builder runs as `ubuntu` (uid 1000) because the upstream `ubuntu:24.04` base image ships a pre-existing `ubuntu:ubuntu` account at uid 1000, and the embedded `distro.ubuntu.base_user` vocabulary adopts it.

Lives in the **`opencharly/distro-ubuntu`** repo (git submodule at **`box/ubuntu`**).
Build it from the submodule: `charly -C box/ubuntu box build ubuntu-builder`
(normally builds implicitly as a dependency of `ubuntu-coder`). Its
`pixi`/`nodejs`/`build-toolchain` candies are pulled by github reference from the
main repo.

## Box Properties

| Property | Value |
|----------|-------|
| Base | `ubuntu` (which = `ubuntu:24.04` + our bootstrap) |
| Layers | `pixi`, `nodejs`, `build-toolchain` |
| Platforms | `linux/amd64` |
| Registry | `ghcr.io/opencharly` |
| User | `ubuntu` / uid 1000 (**adopt mode** — see `/charly-image:image` "user_policy") |
| Home | `/home/ubuntu` |

## Full candy stack

1. `/charly-distros:ubuntu` — Ubuntu 24.04 + bootstrap. Inherits Debian's `apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg` pattern because the embedded `distro.ubuntu` vocabulary declares `inherits: debian`. Ubuntu-specific: `base_user: { name: ubuntu, uid: 1000, gid: 1000, home: /home/ubuntu }` — no `useradd` step emitted.
2. `/charly-languages:pixi` — pixi package manager + env paths (`/home/ubuntu/.pixi`).
3. `/charly-coder:nodejs` — Node.js + npm (generic `nodejs`).
4. `/charly-coder:build-toolchain` — same Debian `-dev` packages as `/charly-distros:debian-builder`.

## Adopt-mode semantics

When the generator emits the Containerfile for this image, the bootstrap section contains:

```
# User ubuntu (uid=1000) adopted from base image (declared in the embedded distro.base_user vocabulary) — no useradd needed
WORKDIR /home/ubuntu
USER 1000
```

No `useradd`, no `groupadd`, no `usermod -l` rename. The upstream `ubuntu:ubuntu` account is honored verbatim — HOME, npm prefix, pixi env, cargo home, sudoers all derive from `resolved.User = "ubuntu"`. See `/charly-image:image` "user_policy" and `/charly-internals:generate-source` "writeBootstrap".

## Role in the build system

Declares `builds: [pixi, npm, cargo]` and is referenced from `ubuntu:` as:

```yaml
ubuntu:
  builder:
    pixi: ubuntu-builder
    npm: ubuntu-builder
    cargo: ubuntu-builder
```

During `charly box build ubuntu-coder`, cargo/npm/pixi-owning candies get their `FROM ubuntu-builder AS <layer>-<type>-build` stages from this image, then `COPY --from=<stage> --chown=1000:1000 /home/ubuntu /home/ubuntu` into the final ubuntu-coder. (The `--chown=1000:1000` numeric form works uniformly regardless of user name — see `/charly-coder:build-toolchain` for the builder-artifact COPY pattern.)

## Cross-distro sibling builders

- `/charly-distros:fedora-builder` — RPM-family, `user:user` uid 1000 (create).
- `/charly-distros:debian-builder` — deb-family, Debian 13, `user:user` (create — Debian 13 ships no pre-existing uid-1000 user).
- `/charly-distros:arch-builder` — pacman-family, `user:user` + `yay` for AUR.

The three builders have near-identical candy stacks (pixi + nodejs + build-toolchain). The only meaningful divergence is this box's adopt-mode `ubuntu:ubuntu` identity.

## Quick start

```bash
charly -C box/ubuntu box build ubuntu-builder
charly shell ubuntu-builder               # drops you into /home/ubuntu as uid 1000
id                                    # uid=1000(ubuntu) gid=1000(ubuntu)
```

Typically not invoked directly — it's a build-time dependency of `/charly-coder:ubuntu-coder`.

## Verification

- `charly -C box/ubuntu box list | grep ubuntu-builder`
- `charly shell ubuntu-builder -- id` → `uid=1000(ubuntu) gid=1000(ubuntu)`
- `charly shell ubuntu-builder -- pixi --version && node --version && gcc --version`

## Related boxes

- `/charly-distros:ubuntu` — parent base; declares `base_user:` in the embedded distro vocabulary.
- `/charly-coder:ubuntu-coder` — the consumer that this builder serves.
- `/charly-distros:debian-builder` — deb-family sibling without adopt mode.
- `/charly-distros:fedora-builder` — canonical RPM-family sibling.

## Related candies

- `/charly-languages:pixi`, `/charly-coder:nodejs`, `/charly-coder:build-toolchain`

## Related commands

- `/charly-build:build` — `base_user:` declaration format in the embedded `distro.*` vocabulary
- `/charly-image:image` — `user_policy:` field (auto / adopt / create) and the decision table
- `/charly-build:generate` — adopt-vs-create writeBootstrap emission modes

## When to use this skill

**MUST be invoked** when:

- Building or troubleshooting `ubuntu-builder` itself.
- Debugging multi-stage COPY-from errors or permission issues in a `ubuntu-coder` build (this is the source stage; uid 1000 = `ubuntu` by adoption).
- Understanding why `${HOME}` = `/home/ubuntu` (not `/home/user`) inside builder stages.
