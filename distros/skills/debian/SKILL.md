---
name: debian
description: |
  Base Debian 13 trixie image. Root of the box hierarchy for Debian builds
  that run as uid 1000 `user` (create mode — Debian 13 ships no pre-existing
  uid-1000 account). Owned by the opencharly/distro-debian submodule (box/debian);
  consumed by no main-repo box.
  MUST be invoked before building, deploying, configuring, or troubleshooting
  any Debian-based box.
---

# debian

Base Debian 13 (trixie) image. Root of the Debian box hierarchy.

The Debian family lives in the **`opencharly/distro-debian`** repo (git submodule at
**`box/debian`**). The `debian` base is **owned there** (in that repo's
`charly.yml`) and composes the main repo's candies by git reference; the
`debian` distro config, the `deb` format, and the `debootstrap` builder
template come from charly's embedded build vocabulary. Build it from the submodule:
`charly -C box/debian box build debian` (or `charly --repo opencharly/distro-debian box build debian`).
Ubuntu — the deb-family sibling — lives in its own **`opencharly/distro-ubuntu`** repo
(see `/charly-distros:ubuntu`). Nothing in main consumes any Debian box, so there
is **no main ↔ debian coupling**.

## Box Properties

| Property | Value |
|----------|-------|
| Base | `debian:13` |
| Pkg | `deb` |
| Distro tags | `["debian:13", "debian"]` |
| Layers | (none — base image only) |
| Platforms | `linux/amd64` |
| User | `user` / uid 1000 (**create mode**) |
| Home | `/home/user` |
| Registry | `ghcr.io/opencharly` |

## User model — create, not adopt

The embedded `distro.debian` vocabulary **does not** declare a `base_user:` block, because the upstream `debian:13` base image ships no pre-existing uid-1000 account. `user_policy: auto` (the default for any downstream image) falls through to create mode — the generator emits an idempotent `useradd -m -u 1000 -g 1000 user` during bootstrap.

This is the intentional asymmetry vs `/charly-distros:ubuntu`, which DOES ship `ubuntu:ubuntu` at uid 1000 and declares `base_user:` to adopt that identity. See `/charly-image:image` "user_policy" and `/charly-build:build` "base_user" for the full decision table.

If you build a downstream image on `debian:13-cloud` (or a similar variant that ships a pre-existing `debian` account), override this by adding a `base_user:` block in your project's `build.yml` override.

## Bootstrap

```dockerfile
FROM debian:13
RUN --mount=type=cache,dst=/var/cache/apt,sharing=locked
    --mount=type=cache,dst=/var/lib/apt,sharing=locked
    apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg && \
    ... install go-task binary ...
RUN if ! getent passwd 1000 >/dev/null 2>&1; then
      (getent group 1000 >/dev/null 2>&1 || groupadd -g 1000 user) &&
      useradd -m -u 1000 -g 1000 -s /bin/bash user;
    fi
WORKDIR /home/user
USER 1000
```

`gnupg` is in the bootstrap package set because downstream candies with `deb.repos[].key` (GitHub CLI, Docker, Kubernetes, Tailscale, Microsoft) call `gpg --dearmor` to convert ASCII-armored keys into `/etc/apt/keyrings/<name>.gpg`. Without `gnupg` the apt-repo stages fail with `gpg: not found`.

## Downstream / sibling entries (all in opencharly/distro-debian)

- `/charly-distros:debian-builder` — pixi/npm/cargo multi-stage builder on this base.
- `/charly-coder:debian-coder` — kitchen-sink dev box on this base.
- `/charly-distros:debian-debootstrap-builder` — privileged debootstrap builder (`base: debian:13`).
- `/charly-distros:debian-debootstrap` — bootstrap-from-scratch rootfs (`from: builder:debootstrap`).
- `/charly-vm:debian` — the `debian-debootstrap` bootstrap VM + `check-debian-debootstrap-vm` bed.

## Verification

```bash
charly -C box/debian box build debian
charly shell debian                       # drops into /home/user as uid 1000
id                                    # uid=1000(user) gid=1000(user)
charly -C box/debian box validate     # embedded build vocab + remote layer refs resolve
```

## Related boxes

- `/charly-distros:ubuntu` — deb-family sibling base in the separate `opencharly/distro-ubuntu` submodule; ships `base_user:` + adopts ubuntu:ubuntu.
- `/charly-distros:debian-builder` — multi-stage builder on top of this box.
- `/charly-coder:debian-coder` — kitchen-sink dev box on this base.
- `/charly-distros:fedora` — RPM-family counterpart.
- `/charly-distros:arch` — pacman-family counterpart (separate `opencharly/distro-arch` submodule).

## Related commands

- `/charly-build:build` — `base_user:` declaration format + bootstrap packages.
- `/charly-image:image` — `user_policy:` reconciliation.
- `/charly-build:generate` — writeBootstrap emission.

## When to use this skill

**MUST be invoked** when:

- Building or troubleshooting the `debian` base image.
- Adding any deb-family box that inherits from `debian` (not `ubuntu`).
- Debugging uid-1000 user issues on a Debian-based box — the answer is almost always "create mode fires, user named `user`."
