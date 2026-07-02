---
name: debian-builder
description: |
  Minimal Debian 13 builder image (pixi + Node.js + build-toolchain) used
  as the multi-stage builder for every box based on Debian — currently
  debian-coder. Produces the pre-compiled pixi envs, npm globals, and
  cargo crates that land in the final runtime image via COPY --from.
  MUST be invoked before building, deploying, configuring, or troubleshooting
  the debian-builder box.
---

# debian-builder

Debian 13 counterpart of `/charly-distros:fedora-builder`. Provides the pixi / npm / cargo build environments so downstream Debian boxes (currently `/charly-coder:debian-coder`) get pre-compiled artifacts from a dedicated builder stage without bloating the final image.

Lives in the **`opencharly/distro-debian`** repo (git submodule at **`box/debian`**).
Build it from the submodule: `charly -C box/debian box build debian-builder`
(normally it builds implicitly as a dependency of `debian-coder`). Its
`pixi`/`nodejs`/`build-toolchain` layers are pulled by github reference from the
main repo.

## Box Properties

| Property | Value |
|----------|-------|
| Base | `debian` (which = `debian:13` + our bootstrap) |
| Layers | `pixi`, `nodejs`, `build-toolchain` |
| Platforms | `linux/amd64` |
| Registry | `ghcr.io/opencharly` |
| User | `user` / uid 1000 (create mode — `debian:13` ships no pre-existing uid-1000 account) |

## Full candy stack

1. `/charly-distros:debian` — Debian 13 + our `apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg` bootstrap + go-task binary + `user:user` uid 1000.
2. `/charly-languages:pixi` — pixi package manager + env paths.
3. `/charly-coder:nodejs` — Node.js + npm (generic `nodejs` — Debian's packaged Node).
4. `/charly-coder:build-toolchain` — gcc, g++, cmake, autoconf, ninja, pkg-config, and the full set of `-dev` libraries (Debian equivalents of Fedora's `-devel`). Used by cargo crates that link system libs (libva, x264, ffmpeg, wayland, xkbcommon, etc.).

## Role in the build system

Declares `builds: [pixi, npm, cargo]` and is listed as `debian-coder`'s builder for all three types via:

```yaml
debian:
  builder:
    pixi: debian-builder
    npm: debian-builder
    cargo: debian-builder
```

During `charly box build debian-coder`, any candy that ships `pixi.toml` / `package.json` / `Cargo.toml` gets a multi-stage `FROM debian-builder AS <layer>-<builder>-build` section emitted by the generator, then `COPY --from=<stage> --chown=${UID}:${GID}` into the final image. See `/charly-internals:generate-source` for the template.

No AUR equivalent (unlike `/charly-distros:arch-builder`) — AUR is an Arch-only concept.

## Cross-distro sibling builders

- `/charly-distros:fedora-builder` — Fedora 43 equivalent (+ `rpmfusion` for x264/ffmpeg/libva headers).
- `/charly-distros:arch-builder` — Arch Linux equivalent + `yay` for AUR.
- `/charly-distros:ubuntu-builder` — Ubuntu 24.04 equivalent; differs from this box mainly in `user:ubuntu` vs `user:user` (adopt mode — see `/charly-distros:ubuntu`).

## Quick start

```bash
charly -C box/debian box build debian-builder
charly shell debian-builder
```

Typically not invoked directly — it's a build-time dependency of `/charly-coder:debian-coder`.

## Verification

- `charly -C box/debian box list | grep debian-builder` — box present.
- `charly shell debian-builder -- pixi --version && node --version && gcc --version`.

## Related boxes

- `/charly-distros:debian` — parent base, declares the bootstrap packages in the embedded `distro:` vocabulary.
- `/charly-coder:debian-coder` — the consumer that this builder exists to serve.
- `/charly-distros:fedora-builder` — RPM-family sibling.
- `/charly-distros:arch-builder` — pacman + AUR sibling.
- `/charly-distros:ubuntu-builder` — Ubuntu 24.04 sibling.

## Related candies

- `/charly-languages:pixi`, `/charly-coder:nodejs`, `/charly-coder:build-toolchain`

## Related commands

- `/charly-build:build` — multi-stage builders, `base_user:` declaration
- `/charly-image:image` — `produce:` + `builder:` fields
- `/charly-build:generate` — COPY-from stage emission

## When to use this skill

**MUST be invoked** when:

- Building or troubleshooting `debian-builder` itself.
- Debugging multi-stage `COPY --from` errors in a `debian-coder` build (the source stage is this image).
- Adding a new builder capability (e.g. a `dotnet` build type) to deb-family images.
