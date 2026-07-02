---
name: thunar
description: |
  Thunar file manager for Sway desktop environments with sway config integration.
  Use when working with file management in Sway desktop containers.
---

# thunar -- Xfce file manager for Sway

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `sway` |
| Install files | `charly.yml`, `task:` |

## Packages

- `thunar` (RPM) -- Xfce file manager

## Usage

```yaml
# charly.yml -- typically used via sway-desktop composition
my-image:
  candy:
    - sway-desktop
```

## Used In Boxes

Part of the `sway-desktop` composition candy. Used transitively in all desktop boxes.

## Related Candies

- `/charly-selkies:sway` -- Sway compositor dependency
- `/charly-selkies:sway-desktop` -- composition that includes this candy
- `/charly-selkies:xfce4-terminal` -- terminal emulator (also in sway-desktop)

## When to Use This Skill

Use when the user asks about:

- Thunar file manager in Sway containers
- File browsing in desktop boxes
- Sway desktop application configuration

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
