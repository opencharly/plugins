---
name: chrome-sway
description: |
  Google Chrome running on Sway compositor via exec autostart with DevTools protocol.
  Use when working with Chrome in Sway, browser automation, or CDP in desktop containers.
---

# chrome-sway -- Chrome browser on Sway compositor

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `sway` |
| Candies (includes) | `chrome` |
| Install files | `task:`, `chrome-sway.conf` |

## Usage

```yaml
# charly.yml -- typically included via sway-desktop composition
my-browser:
  candy:
    - chrome-sway
```

## Used In Boxes

Part of `/charly-selkies:sway-desktop` composition.

## Chrome Lifecycle in Sway

Chrome is launched by Sway's `exec` directive (autostart) via `chrome-wrapper`. It is **not** a supervisord service -- Sway owns the Chrome process. This means:

- **Autostart**: Chrome starts when Sway starts (via `exec chrome-wrapper` in sway config).
- **Crashes/exits**: Chrome does not auto-restart. If Chrome exits, it must be relaunched manually.
- **Manual restart**: Relaunch Chrome with a `wl: exec` step running `chrome-wrapper` (the `wl:` verb dispatches out-of-process via candy/plugin-wl). Do **not** use `charly shell` with bare `swaymsg` -- the shell may lack the correct `SWAYSOCK` path.
- **On-demand launch**: The `browser-open` helper auto-launches Chrome if it's not running (see `/charly-selkies:chrome` for details).

## Related Candies

- `/charly-selkies:sway` -- compositor dependency
- `/charly-selkies:chrome` -- Chrome browser and DevTools (included via candies)
- `/charly-selkies:sway-desktop` -- composition that includes chrome-sway
- `/charly-selkies:wayvnc` -- VNC access to see Chrome desktop

## When to Use This Skill

Use when the user asks about:

- Chrome running in Sway desktop
- Browser autostart in compositor
- CDP (Chrome DevTools Protocol) in desktop containers
- Chrome-sway configuration

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
