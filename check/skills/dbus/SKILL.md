---
name: dbus
description: |
  D-Bus interaction inside containers via the declarative `dbus:` check verb,
  served out-of-process by `candy/plugin-dbus` (EXEC-based, `gdbus` over the
  executor reverse channel).
  MUST be invoked before any work involving: the `dbus:` check verb, desktop
  notifications, D-Bus method calls, service introspection, or session bus
  interaction.
---

# D-Bus -- D-Bus Interaction Inside Containers

## Overview

The `dbus:` check verb sends desktop notifications, calls D-Bus methods, lists
services, and introspects objects on the venue's D-Bus **session bus**. It is
**NOT a host `charly check` subcommand** — it is a declarative check verb served
out-of-process by its plugin (`candy/plugin-dbus`), parallel to the
`cdp:`/`vnc:`/`mcp:`/`record:` plugin verbs. Author a `dbus:` step in a candy/box
plan and run it against a live deployment with
`charly check live <image> --filter dbus`.

**Served out-of-process — no host CLI subcommand.** `dbus` is EXEC-based: the host
dispatches the `dbus:` verb through the provider registry exactly like a built-in
(`ResolveVerb("dbus")` → the out-of-process gRPC provider → `Provider.Invoke` with
the full `Op`), and the plugin drives the venue's session bus with `gdbus` (from
`glib2`) over charly's live `DeployExecutor` reverse channel — there is no
pre-resolved endpoint and no in-container `charly` binary involved. Authoring is
unchanged from a built-in verb: you write `dbus: notify`, never `plugin: dbus`.

### Authoring a `dbus:` step

Each method is the declarative `dbus:` step you author — an ordered list item under
the candy/box `plan:`. The method name (list/call/introspect/notify) is the scalar
value for a bare-method step (`dbus: list`), or the `method:` key of the `dbus:` map
when the step carries dbus-exclusive fields (`dest:`, `path:`, `member:`, `arg:`,
`text:`) — those live INSIDE the `dbus:` map. The shared matchers (`stdout:`,
`stderr:`, `exit_status:`) and `description:` (the notify body, doubling as the step's
report label) stay siblings of the `dbus:` key. All `dbus:` steps are
**deploy-context only** (they need a running session bus), so author them with
`context: [deploy]`. See `/charly-check:check` for the full YAML shape. Example:

```yaml
- check: the notifications service is on the session bus
  context: [deploy]
  dbus: list
  stdout:
    contains: org.freedesktop.Notifications
```

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Send notification | `dbus: notify` + `text:` (+ sibling `description:` body) | Desktop notification via the Notifications interface |
| Call method | `dbus: call` + `dest:` + `path:` + `member:` (+ optional `arg:`) | Generic D-Bus method call |
| List services | `dbus: list` | List all registered session bus services |
| Introspect | `dbus: introspect` + `dest:` + `path:` | Introspect a service's interfaces and methods |

The `+ <field>:` entries (except `description:`) are keys INSIDE the `dbus:` map;
`description:` and the `stdout:`/`stderr:`/`exit_status:` matchers stay siblings.

Run a candy's baked `dbus:` steps against a live deployment with
`charly check live <image> --filter dbus`.

## Methods

Each method below is the declarative `dbus:` step you author; queries produce
assertable output (run them as `check:` steps), side-effect actions pass when they
exit 0 (run them as `run:` steps). All steps are deploy-context only.

### Desktop Notifications

```yaml
- check: a desktop notification is delivered
  context: [deploy]
  dbus:
    method: notify
    text: Build Complete           # notification summary (dbus-exclusive, in the map)
  description: Image built successfully   # notification body (shared #Op sibling)
```

Calls `org.freedesktop.Notifications.Notify` on the session bus; the notification
appears via the running notification daemon (swaync or mako).

### Generic Method Calls

```yaml
- check: the notifications service reports its capabilities
  context: [deploy]
  dbus:
    method: call
    dest: org.freedesktop.Notifications
    path: /org/freedesktop/Notifications
    member: org.freedesktop.Notifications.GetCapabilities   # the interface.Method to call
    # arg: [...]                  # optional typed call arguments (type:value)
```

Calls an arbitrary D-Bus method on the session bus and returns its reply.

### List Services

```yaml
- check: the session bus has the expected services registered
  context: [deploy]
  dbus: list
  stdout:
    contains: org.freedesktop.Notifications
```

Lists all registered services on the venue's session bus.

### Introspect a Service

```yaml
- check: the notifications object exposes the Notify method
  context: [deploy]
  dbus:
    method: introspect
    dest: org.freedesktop.Notifications
    path: /org/freedesktop/Notifications
  stdout:
    contains: Notify
```

Introspects a service object's interfaces, methods, signals, and properties.

## Prerequisites

- Container must have a D-Bus session bus running (provided by the `dbus` layer)
- `gdbus` must be present in the venue (from `glib2` — the plugin drives it over
  the reverse channel)
- For notifications: a notification daemon must be running (e.g., `swaync`)
- Container must be running (`charly start <image>`)

## Cross-References

- `/charly-check:check` -- parent router; the `dbus:` verb dispatches out-of-process via `candy/plugin-dbus`, and `charly check live <image> --filter dbus` runs a candy's baked steps.
- `/charly-internals:plugin` -- the out-of-process provider model that serves `dbus` (the EXEC-based `gdbus`-over-reverse-channel plugin).
- `/charly-check:cdp` -- Chrome DevTools Protocol automation (sibling out-of-process verb served by `candy/plugin-cdp`).
- `/charly-check:vnc` -- VNC desktop automation (sibling out-of-process verb served by `candy/plugin-vnc`).
- `/charly-check:wl` -- Wayland desktop automation (sibling out-of-process verb served by `candy/plugin-wl`).
- `/charly-core:cmd` -- single command execution in running containers (its best-effort completion notification drives the session bus via `gdbus` from the host).
- `/charly-core:shell` -- interactive shell access
- `/charly-infrastructure:dbus-layer` -- D-Bus session bus layer configuration
- `/charly-selkies:swaync` -- notification daemon layer
