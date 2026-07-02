---
name: fastfetch
description: |
  Fast system information tool (neofetch successor).
  Use when working with the fastfetch candy.
---

# fastfetch -- Fast system information tool

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages only) |
| Depends | none |

## Packages

RPM: `fastfetch`

## What It Does

Displays system information (OS, kernel, CPU, GPU, memory, etc.) with ASCII art logo. Active successor to the archived neofetch project. Useful for verifying container environment and creating visual demos.

## Usage

```yaml
# a box composing this candy — the candy list is a child node
my-box:
  candy:
    base: fedora
  my-box-candy:
    candy:
      - fastfetch
```

## Included In

- `sway-desktop` metalayer (and all sway-desktop-* variants)
- `selkies-desktop` metalayer (and all selkies-desktop-* variants)

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Candies
- `/charly-selkies:sway-desktop` — Metalayer that pulls fastfetch in
- `/charly-selkies:selkies-desktop-layer` — Metalayer that pulls fastfetch in
- `/charly-coder:dev-tools` — Sibling that also packages fastfetch via dnf

## Related Commands
- `/charly-build:build` — Builds the fastfetch RPM into the box
- `/charly-core:shell` — Interactive shell to run `fastfetch` for environment verification

## When to Use This Skill

Use when the user asks about:
- System information display in containers
- fastfetch or neofetch in containers
- The `fastfetch` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, `run:`/`check:` step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
