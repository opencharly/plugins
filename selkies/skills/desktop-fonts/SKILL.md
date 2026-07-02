---
name: desktop-fonts
description: |
  JetBrains Mono and Nerd Fonts for desktop containers.
  Use when working with font configuration or desktop text rendering.
---

# desktop-fonts -- JetBrains Mono + Nerd Fonts

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | none |
| Service | none |
| Install files | `charly.yml` only |

## Packages

- `jetbrains-mono-fonts` (RPM) -- monospace coding font
- `liberation-fonts` (RPM) -- serif/sans/mono web fonts (Chrome rendering fallback)
- `nerd-fonts` (RPM, via `che/nerd-fonts` COPR) -- icon font (Symbols Nerd Font)

**Fedora 43 package-name note:** `liberation-fonts` is a **virtual**
package — dnf resolves it to `liberation-sans-fonts` (and sibling
`-serif-fonts` / `-mono-fonts` packages). Any `package:` test must
query the real installed name (`liberation-sans-fonts`), not the
dnf-level request. See `/charly-check:check` Authoring Gotcha #8.

## Usage

Included in desktop metalayers. Not typically added directly:

```yaml
# Already part of sway-desktop and selkies-desktop metalayers
```

## Notes

- The `che/nerd-fonts` COPR is enabled before install and disabled after (declarative `copr:` field)
- Provides `Symbols Nerd Font` and `Symbols Nerd Font Mono` for waybar icons and swaync
- JetBrains Mono is the primary font for waybar and swaync Catppuccin Mocha theme

## Used In

- `/charly-selkies:sway-desktop` -- via metalayer composition
- `/charly-selkies:selkies-desktop-layer` -- via metalayer composition

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Skills

- `/charly-selkies:waybar` -- uses JetBrains Mono + Symbols Nerd Font
- `/charly-selkies:waybar-labwc` -- same fonts
- `/charly-selkies:swaync` -- uses JetBrains Mono
- `/charly-check:check` -- declarative testing framework (Authoring Gotcha #8 on package renames)
- `/charly-image:layer` -- candy authoring reference

## When to Use This Skill

Use when the user asks about:

- Font configuration in desktop containers
- Nerd Font icons in waybar or terminal
- JetBrains Mono font availability
