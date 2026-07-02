---
name: qemu-guest-agent
description: |
  QEMU guest agent for host-guest communication in virtual machines.
  Use when working with QEMU/KVM VMs, guest agent setup, or libvirt channel configuration.
---

# qemu-guest-agent -- QEMU guest agent

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` |

## Packages

- `qemu-guest-agent` -- QEMU guest agent daemon. The package name is identical on
  Arch/CachyOS (`pac`) and Fedora (`rpm`), so the top-level `package:` covers both
  — this is a cross-distro candy, not RPM-only.

## Full functionality (all RPCs + fsfreeze)

The candy exposes the **complete** guest-agent surface — `guest-exec`,
`guest-file-*`, `guest-fsfreeze-*`, `guest-set-*`. The package default blocks no
RPCs; the candy's `/etc/qemu/qemu-ga.conf` makes that explicit and turns on the
**fsfreeze hook** (the one capability not active by default), so the host can take
application-consistent snapshots. The hook is a standard dispatcher
(`/etc/qemu/fsfreeze-hook`) that runs every executable in
`/etc/qemu/fsfreeze-hook.d/` with `freeze`/`thaw`; drop per-app scripts there.

The candy also enables the `qemu-guest-agent.service` (system scope) and
contributes the virtio-serial channel (below). On a `kind: vm` entity the channel
is usually declared structurally instead — `channels: [{type: unix, name:
org.qemu.guest_agent.0}]` (see `/charly-internals:libvirt-renderer`).

## Usage

```yaml
# charly.yml -- add to a bootc image's layer list
my-vm-image:
  bootc: true
  candy:
    - qemu-guest-agent
# or applied to a VM guest at deploy time:
#   charly bundle add vm:<name> qemu-guest-agent
```

## Used In Boxes

Composed into bootc images directly, or applied to a VM guest at deploy time (`charly bundle add vm:<name> qemu-guest-agent`).

## virtio-serial channel (libvirt XML contribution)

The candy contributes a raw libvirt XML snippet that the libvirt renderer places in the VM's `<devices>` section:

```xml
<channel type='unix'>
  <target type='virtio' name='org.qemu.guest_agent.0'/>
</channel>
```

Emitted in `charly.yml` as:

```yaml
libvirt:
  snippets:
    - "<channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>"
```

This is the `/` classification case: `isDeviceElement` flags it as device-scoped, so the renderer injects it inside `<devices>` rather than before `</domain>`. See `/charly-internals:libvirt-renderer` for the injection pipeline and `/charly-vm:vm` for the QEMU-user-net caveat (the agent shows as enabled/inactive under `charly`'s QEMU backend; libvirt backend activates it).

## Related Candies

- `/charly-coder:sshd` -- SSH server (commonly paired in bootc/VM images)

## When to Use This Skill

Use when the user asks about:

- QEMU guest agent installation
- Host-guest communication in VMs
- Libvirt virtio channel configuration
- The `org.qemu.guest_agent.0` channel

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations, `libvirt.snippets:`)
- `/charly-vm:vm` — VM lifecycle; bootc VM caveats; QEMU-user-net limitation
- `/charly-vm:vms-catalog` — `kind: vm` entity schema that consumes this candy's contribution
- `/charly-internals:libvirt-renderer` — renderer that injects this candy's snippet into `<devices>`
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
