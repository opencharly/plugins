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

Each method is the declarative `dbus:` step you author: the method name
(list/call/introspect/notify) is the verb's YAML value, and method-specific fields
(`dest:`, `path:`, `method:`, `args:`, `text:`, `description:`) are siblings of the
verb line. Shared matchers (`stdout:`, `stderr:`, `exit_status:`) work like every
other verb. All `dbus:` steps are **deploy-context only** (they need a running
session bus), so author them with `context: [deploy]`. See `/charly-check:check`
for the full YAML shape. Example:

```yaml
notifications-registered:
    check: the notifications service is on the session bus
    dbus: list
    context: [deploy]
    stdout:
        contains: org.freedesktop.Notifications
```

## Quick Reference

| Action | Declarative step | Description |
|--------|------------------|-------------|
| Send notification | `dbus: notify` + `text:` (+ optional `description:`) | Desktop notification via the Notifications interface |
| Call method | `dbus: call` + `dest:` + `path:` + `method:` (+ optional `args:`) | Generic D-Bus method call |
| List services | `dbus: list` | List all registered session bus services |
| Introspect | `dbus: introspect` + `dest:` + `path:` | Introspect a service's interfaces and methods |

Run a candy's baked `dbus:` steps against a live deployment with
`charly check live <image> --filter dbus`.

## Methods

Each method below is the declarative `dbus:` step you author; queries produce
assertable output (run them as `check:` steps), side-effect actions pass when they
exit 0 (run them as `run:` steps). All steps are deploy-context only.

### Desktop Notifications

```yaml
notify-build-done:
    check: a desktop notification is delivered
    dbus: notify
    context: [deploy]
    text: Build Complete           # notification summary
    description: Image built successfully   # notification body
```

Calls `org.freedesktop.Notifications.Notify` on the session bus; the notification
appears via the running notification daemon (swaync or mako).

### Generic Method Calls

```yaml
notifications-capabilities:
    check: the notifications service reports its capabilities
    dbus: call
    context: [deploy]
    dest: org.freedesktop.Notifications
    path: /org/freedesktop/Notifications
    method: org.freedesktop.Notifications.GetCapabilities
    # args: [...]                  # optional method arguments
```

Calls an arbitrary D-Bus method on the session bus and returns its reply.

### List Services

```yaml
list-services:
    check: the session bus has the expected services registered
    dbus: list
    context: [deploy]
    stdout:
        contains: org.freedesktop.Notifications
```

Lists all registered services on the venue's session bus.

### Introspect a Service

```yaml
introspect-notifications:
    check: the notifications object exposes the Notify method
    dbus: introspect
    context: [deploy]
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
- `/charly-check:wl` -- Wayland desktop automation (sibling in-core host verb under `charly check`).
- `/charly-core:cmd` -- single command execution in running containers (its best-effort completion notification drives the session bus via `gdbus` from the host).
- `/charly-core:shell` -- interactive shell access
- `/charly-infrastructure:dbus-layer` -- D-Bus session bus layer configuration
- `/charly-selkies:swaync` -- notification daemon layer
