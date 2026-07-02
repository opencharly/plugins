---
name: xfce4-terminal
description: |
  Xfce4 terminal emulator for Sway desktop environments with sway config integration.
  Use when working with terminal emulators in Sway desktop containers.
---

# xfce4-terminal -- terminal emulator for Sway

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `sway` |
| Install files | `charly.yml`, `task:` |

## Packages

- `xfce4-terminal` (RPM) -- Xfce terminal emulator

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
- `/charly-selkies:thunar` -- file manager (also in sway-desktop)

## When to Use This Skill

Use when the user asks about:

- Terminal emulator in Sway containers
- Xfce4 terminal configuration
- Sway desktop terminal access

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
