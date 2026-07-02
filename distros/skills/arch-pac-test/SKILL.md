---
name: arch-pac-test
description: |
  Test candy for pacman package installation on Arch Linux.
  Use when working with the arch-pac-test candy.
---

# arch-pac-test -- Arch pacman package test

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

PAC: `neovim`, `ripgrep`

## What It Does

Validates that the `pac:` package format works correctly on Arch Linux boxes. Installs neovim and ripgrep via pacman. Used as a smoke test for the multi-distro build system's Arch support.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    base: arch
  my-image-candy:
    candy:
      - arch-pac-test
```

Requires an Arch-based box with `build: [pac]` (or `[pac, aur]`).

## Used In Boxes

- `/charly-distros:arch-test` — Arch packaging test box

## Related Candies

- `/charly-distros:arch-aur-test` — companion AUR package test

## When to Use This Skill

Use when the user asks about:
- Arch Linux pacman package testing
- The `pac:` package format in charly.yml
- The `arch-pac-test` candy

## Author + Test References

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan steps, service declarations)
- `/charly-check:check` — declarative testing framework for the `check:` block
