---
name: swaync
description: |
  SwayNotificationCenter notification daemon for wlroots compositors (sway, labwc).
  Use when working with desktop notifications, notification center, or swaync configuration.
---

# swaync -- SwayNotificationCenter

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `dbus` |
| Service | `swaync` (supervisord, priority 14, startsecs=2) |
| Install files | `charly.yml`, `task:`, `swaync-wrapper`, `config.json`, `style.css` |

## Packages

- `SwayNotificationCenter` (RPM) -- provides `swaync`, `swaync-client`

## Service

Runs as a supervisord service (priority 14, `startsecs=2`) via `swaync-wrapper` which waits for the Wayland socket before starting. The wrapper uses `pkill -9 -x swaync` (exact name match) to kill any stale instance before exec, preventing D-Bus name conflicts on restart. `startsecs=2` gives swaync time to claim the D-Bus name before supervisord declares it running. Priority 14 ensures swaync starts after the compositor (10-12) but before waybar (15), so the notification indicator module is ready.

### D-Bus Auto-Activation Fix

The `task:` removes D-Bus auto-activation service files (`org.erikreider.swaync.service`, `org.erikreider.swaync.cc.service`) at build time. Without this fix, D-Bus spawns a competing swaync instance when waybar's `swaync-client -swb` queries the notification service ~2 seconds after startup. The `SystemdService=` directive in those files is intended to delegate to systemd, but since containers use supervisord (not systemd as PID 1), D-Bus falls back to `Exec=/usr/bin/swaync`, creating a second instance that steals the D-Bus bus name from the supervisord-managed one — causing the supervisord instance to exit with FATAL status.

## Configuration

### config.json (`~/.config/swaync/config.json`)

- Notification panel on right side, overlay layer
- Widgets: inhibitors, title, dnd (Do Not Disturb), mpris (media), notifications
- Timeouts: 6s normal, 4s low, 0s critical (stays visible)
- Control center: 420px wide, top-right corner

### style.css (`~/.config/swaync/style.css`)

Catppuccin Mocha theme matching waybar:
- Color-coded notification priorities: blue (normal), red (critical), gray (low)
- MPRIS media player widget
- DnD toggle switch
- Rounded corners, semi-transparent backgrounds

## Waybar Integration

The waybar `custom/notification` module displays a notification bell icon using swaync-client:
- Click: toggle notification panel (`swaync-client -t`)
- Right-click: toggle Do Not Disturb (`swaync-client -d`)
- Icons use Nerd Font symbols (from `desktop-fonts` candy)

## Compositor Compatibility

Works with any wlroots compositor via `wlr-layer-shell` protocol:
- **sway** -- replaces mako (mako removed from sway layer)
- **labwc** -- first notification daemon (none was previously included)

## Testing Notifications

Send and verify notifications declaratively with the `dbus:` check verb (served
out-of-process by `candy/plugin-dbus`, driving the session bus with `gdbus` — no
shell quoting issues), run with `charly check live <image> --filter dbus`:

```yaml
notify-test:
    check: a desktop notification is delivered
    dbus: notify
    context: [deploy]
    text: Title
    description: Body text
notifications-registered:
    check: swaync is receiving notifications
    dbus: list
    context: [deploy]
    stdout:
        contains: Notifications
```

Host-side alternatives:

```bash
# charly cmd with completion notification (gdbus, host-side)
charly cmd <image> "sleep 2 && echo done"

# Low-level: notify-send (requires libnotify layer)
charly cmd <image> "notify-send 'Title' 'Body text'" --no-notify

# swaync-client operations
charly cmd <image> "swaync-client -c"    # notification count
charly cmd <image> "swaync-client -C"    # clear all
charly cmd <image> "swaync-client -t"    # toggle panel
charly cmd <image> "swaync-client -d"    # toggle DnD
```

## Used In

- `/charly-selkies:sway-desktop` -- via metalayer composition
- `/charly-selkies:selkies-desktop-layer` -- via metalayer composition

## Used In Boxes

- `/charly-selkies:sway-browser-vnc` (via `sway-desktop` metalayer)
- `/charly-selkies:selkies-labwc` (via `selkies-desktop` metalayer)
- `/charly-selkies:selkies-labwc-nvidia` (via `selkies-desktop` metalayer)

## Related Candies

- `/charly-infrastructure:dbus-layer` -- D-Bus session bus dependency
- `/charly-selkies:libnotify` -- `notify-send` CLI (optional; the `dbus: notify` check verb uses `gdbus` instead)
- `/charly-selkies:waybar` -- notification bell module
- `/charly-selkies:waybar-labwc` -- same notification bell module
- `/charly-selkies:desktop-fonts` -- Nerd Font icons for notification bell

## When to Use This Skill

Use when the user asks about:

- Desktop notifications in containers
- SwayNotificationCenter configuration or styling
- Notification bell in waybar
- Do Not Disturb mode

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
