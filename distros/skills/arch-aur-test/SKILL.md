---
name: arch-aur-test
description: |
  Test candy for AUR package installation on Arch Linux.
  Use when working with the arch-aur-test candy.
---

# arch-aur-test -- Arch AUR package test

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

AUR: `yay-bin`

## What It Does

Validates that the `aur:` package format works correctly on Arch Linux boxes. Installs the `yay-bin` package from the AUR. Requires a builder image with `builds: [aur]` capability (i.e., `arch-builder` which includes the `yay` candy).

## Usage

```yaml
# charly.yml
my-image:
  candy:
    base: arch
    candy: [arch-aur-test]
```

Requires an Arch-based box with `build: [pac, aur]` so the builder can resolve AUR packages.

## Used In Boxes

- `/charly-distros:arch-test` — Arch packaging test box

## Related Candies

- `/charly-distros:arch-pac-test` — companion pacman package test
- `/charly-tools:yay` — AUR helper that enables `aur:` builds

## When to Use This Skill

Use when the user asks about:
- Arch Linux AUR package testing
- The `aur:` package format in charly.yml
- The `arch-aur-test` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
