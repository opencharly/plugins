---
name: dbus-layer
description: |
  D-Bus session bus for inter-process communication inside containers.
  Use when working with D-Bus, desktop services, Wayland compositor dependencies, or the `dbus:` check verb.
---

# dbus -- D-Bus session bus service

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Service | `dbus` (supervisord, priority 2) |
| Install files | `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `DBUS_SESSION_BUS_ADDRESS` | `unix:path=/tmp/dbus-session` |

## Packages

- `dbus-daemon` (RPM)

## Cross-distro coverage

RPM: `dbus-daemon` (Fedora) · PAC: `dbus` (Arch) · DEB: `dbus` (Debian/Ubuntu). Full parity — same DBUS_SESSION_BUS_ADDRESS env, same supervisord fragment, identical behavior downstream.

## Usage

```yaml
# charly.yml -- now included in all images with supervisord
my-image:
  candy:
    - dbus
```

## The `dbus:` check verb

The `dbus:` check verb drives this session bus from a candy/box plan. It is a
declarative verb served out-of-process by `candy/plugin-dbus` (EXEC-based: the
plugin drives `gdbus` from `glib2` over charly's `DeployExecutor` reverse channel);
there is no host `charly check dbus` subcommand. Author `dbus: list`/`call`/
`introspect`/`notify` steps with `context: [deploy]` and run them with
`charly check live <image> --filter dbus`. See `/charly-check:dbus` for the full
method catalog and YAML shape.

### Notification Delivery Chain

`charly cmd` → `sendVenueNotification()` → `gdbus call ... org.freedesktop.Notifications.Notify` → swaync/mako → desktop popup

For notifications to work, the box needs:
1. **`dbus` candy** — D-Bus session bus (this candy)
2. **`swaync` candy** — notification daemon
3. **`gdbus`** (from `glib2`) in the venue — the host drives it over the reverse channel

## `charly status` Probe

The `dbus` probe checks:
1. Whether `dbus-daemon` process is running
2. Which notification daemon is active (swaync, mako, dunst)

Shows as `dbus:ok (notify:swaync)` in `charly status` detail view.

## Used In Boxes

- Transitive dependency via `sway` in all desktop boxes
- Now explicitly added to all boxes with supervisord (openclaw, jupyter, ollama, immich, etc.)

## Related Candies

- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-selkies:sway` -- primary consumer (Sway depends on dbus)
- `/charly-selkies:swaync` -- notification daemon (depends on dbus)
- `/charly-selkies:libnotify` -- `notify-send` CLI tool (depends on dbus)

## Related Commands

- `/charly-check:dbus` — the declarative `dbus:` check verb (notify, list, call, introspect), served out-of-process by `candy/plugin-dbus`

## When to Use This Skill

Use when the user asks about:

- D-Bus session bus configuration
- `DBUS_SESSION_BUS_ADDRESS` environment variable
- the `dbus:` check verb (notify, call, list, introspect)
- Desktop notifications in containers
- Inter-process communication in containers

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
