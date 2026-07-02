---
name: rpmfusion
description: |
  RPM Fusion free and nonfree repository configuration for Fedora.
  Use when working with RPM Fusion repos, multimedia codecs, or nonfree packages.
---

# rpmfusion -- RPM Fusion repository configuration

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `task:` |

## Usage

```yaml
# charly.yml
fedora-nonfree:
  base: fedora
  candy:
    - rpmfusion
```

## Used In Boxes

- `/charly-distros:fedora-nonfree` (base for immich and other boxes needing nonfree packages)
- `/charly-distros:fedora-builder` — applied **before** `build-toolchain` so cargo crates that
  need RPM Fusion free system libs (`libva-devel`, `x264-devel`, `ffmpeg-devel`) can install
  via dnf in the builder stage. Required for building pixelflux from source — see
  `/charly-selkies:selkies` (Patched pixelflux build pipeline).

## Related Candies
- `/charly-selkies:ffmpeg` -- nonfree multimedia codecs installed from RPM Fusion
- `/charly-immich:immich` -- consumes nonfree codecs via fedora-nonfree

## Related Commands
- `/charly-build:build` -- build the fedora-nonfree base image
- `/charly-image:image` -- inspect base/box inheritance

## When to Use This Skill

Use when the user asks about:

- RPM Fusion repository setup
- Nonfree or multimedia packages on Fedora
- The `fedora-nonfree` base image
- Enabling additional Fedora repositories

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
