---
name: libvirt
description: the `libvirt:` libvirt-RPC check verb for VMs — domain info, framebuffer screenshots, send-key, passwd, QMP, qemu-guest-agent client, snapshots, events — served out-of-process by candy/plugin-vm.
allowed-tools: Bash, Read
---

# libvirt — VM libvirt-RPC check verb

## Overview

`libvirt:` is a DECLARATIVE check verb — authored as `libvirt: <method>` inside
a candy/box plan `check:`/`run:` step. It is **NOT a host `charly check`
subcommand** — a declarative check verb served out-of-process by
`candy/plugin-vm` (nested under `charly check` at runtime), parallel to the
`kube:`/`adb:`/`appium:` plugin verbs. The VM/libvirt-API implementation (and
the `go-libvirt` + `kata-containers/govmm` + `libvirt.org/go/libvirtxml`
dependencies) lives entirely in that external plugin, NOT in charly's core; at
check time the host dispatches `libvirt:` through the provider registry to the
out-of-process plugin (the same path a bed's checks take via `charly check
live` / `charly check run`).

The verb maps every libvirt-RPC management/introspection surface a VM needs
beyond what `charly vm` (lifecycle) provides — domain info, framebuffer
capture, keyboard injection, live graphics-password patching, QMP passthrough,
the qemu-guest-agent client, snapshots, and lifecycle events. **VM-only** — it
needs a running libvirt domain.

### The host pre-resolves the VM target; the plugin speaks libvirtd

charly core owns NO go-libvirt. The host pre-resolves the target's **per-deploy
DOMAIN IDENTITY** host-side and passes it (`Runner.vmTargetName()` — the deploy name via
`vmDomainIdentity`, NOT the shared `kind:vm` entity, P33) to the plugin, so the verb addresses
the live domain `charly-<deploy>` — correctly distinct per bed even when several beds share one
`kind:vm` entity. The plugin opens the libvirtd session connection and runs the method. Authoring is unchanged from a
built-in verb: you write `libvirt: info`, never `plugin: libvirt`.

### Authoring a `libvirt:` step

The method name is the scalar value for a bare-method step (`libvirt: info`), or
the `method:` key of the `libvirt:` map when the step carries libvirt-exclusive
fields (`text:`, `input:`, `key:`, `command:`, `uri:`, `artifact:` and the artifact
validators) — those live INSIDE the `libvirt:` map. Two things stay step-level
siblings of the `libvirt:` key: the shared matchers (`stdout:`, `stderr:`,
`exit_status:`) AND the `target:` snapshot name (a genuinely shared `#Op` modifier
the `snapshot/*` methods read). A query/probe is a `check:` step; an action that
changes domain state (send-key, passwd, snapshot create/revert) is a `run:` step.
**`context: [deploy]`** — the verb needs a running VM; under `charly check
box` (no running VM) it skips. Run a candy's baked `libvirt:` steps against a
live VM deployment with `charly check live <vm> --filter libvirt`.

## Method surface

Every method below is the `libvirt:` map's `method:` (or the scalar value for a
bare method). The Modifiers column names the libvirt-exclusive fields that live
INSIDE the `libvirt:` map — EXCEPT `target:` (the `snapshot/*` name), which is a
shared `#Op` sibling of the `libvirt:` key.

**Top-level:**

| `libvirt:` value | Modifiers | Description |
|---|---|---|
| `list` | — | all domains on the session |
| `info` | — | state + graphics + uptime + agent |
| `screenshot` | `artifact:` (+ `artifact_*` validators) | libvirt `DomainScreenshot` → PNG |
| `send-key` | `key:` | keyboard injection (Linux keycode set); chord notation (`key: "ctrl+alt+F2"`) |
| `passwd` | `text:` | live graphics password patch |
| `qmp` | `text:` (QMP command) + `input:` (JSON args) | QMP passthrough |
| `domain-xml` | — | dump the live domain XML |
| `events` | — | poll lifecycle state transitions |
| `console` | — | (stub) serial console — use `charly vm console <vm>` |

**`guest/*` — qemu-guest-agent client:**

| `libvirt:` value | Modifiers | Description |
|---|---|---|
| `guest/ping` | — | reach the agent |
| `guest/info` | — | agent capability list |
| `guest/os-info` | — | distro/kernel |
| `guest/time` | — | guest clock + host delta |
| `guest/hostname` | — | guest hostname |
| `guest/users` | — | logged-in users |
| `guest/interfaces` | — | IPs + MACs + stats |
| `guest/disks` | — | block devices |
| `guest/fsinfo` | — | mounted filesystems |
| `guest/vcpus` | — | guest-side online state |
| `guest/exec` | `command:` | run a command via `guest-exec` |
| `guest/fstrim` | — | run TRIM on guest filesystems |

**`snapshot/*`:**

| `libvirt:` value | Modifiers | Description |
|---|---|---|
| `snapshot/list` | — | list snapshots |
| `snapshot/create` | `target:` (snapshot name) | create a snapshot |
| `snapshot/info` | `target:` | show snapshot XML |
| `snapshot/revert` | `target:` | revert to a snapshot |
| `snapshot/delete` | `target:` | delete a snapshot |

The `libvirt: <method>` value validates against this method set — the
`#LibvirtMethod` enum, now the `method:` field of the plugin's own `#LibvirtInput`
schema (`candy/plugin-vm/schema/vm.cue`), served over the Describe channel and
spliced onto the base — at `charly box validate` time.

### Nested-runtime operator commands (beyond the declarative set)

A handful of qemu-guest-agent ops carry no declarative method — `guest file
read`/`guest file write` and `guest fsfreeze status`/`freeze`/`thaw`, plus the
ad-hoc flags `--screen N` (screenshot), `--hold` (send-key), `--type
spice|vnc` / `--persistent` (passwd), `--config` (domain-xml), and `--duration`
(events/console). Because the verb is also surfaced under `charly check` at
runtime (dispatched through the provider registry, like `kube`/`adb`/`appium`), reach those
through the nested out-of-process command `charly check libvirt guest file …` /
`charly check libvirt guest fsfreeze …` for interactive operator use. They are
NOT part of the declarative `libvirt:` step vocabulary.

## What it does

Every method maps to one go-libvirt RPC (plus, for `guest/*`, the
`QEMUDomainAgentCommand` passthrough). The method name mirrors the
libvirt/virsh vocabulary so skills translate cleanly. Design choices:

- **Target resolution** identical to the `spice:` verb's host-side
  pre-resolution: the resolved per-deploy DOMAIN IDENTITY (`Runner.vmTargetName()`,
  P33) → the `charly-<deploy>` libvirt domain → live XML via
  `libvirtxml.Domain`. Errors are the same across both.
- **Framebuffer screenshot** (`libvirt: screenshot`) goes through
  `DomainScreenshot` — QEMU's VNC framebuffer capture, returned as PPM, decoded
  in-process and re-encoded as PNG. Independent of whichever graphics protocol
  (SPICE or VNC) the VM exposes on the wire.
- **send-key** uses the Linux keycode set via `DomainSendKey`. A friendly
  keyname map in `candy/plugin-vm/libvirt_ops.go` covers
  letters/digits/modifiers/arrows/function keys. Supports chord notation
  (`key: "ctrl+alt+F2"`).
- **passwd** patches the `<graphics type="spice|vnc" passwd="…">` attribute via
  `libvirtxml`, then calls `DomainUpdateDeviceFlags(LIVE)`.
- **qmp** passes JSON commands through unchanged (`text:` = the QMP method name,
  `input:` = the JSON args). Flag 0 = QMP; HMP not exposed.
- **guest/exec** uses `guest-exec` + polls `guest-exec-status` until exit
  (`command:` carries the argv). stdout/stderr are base64-decoded from the agent
  reply.
- **events** is a 1-Hz lifecycle poller (not callback-based) — good enough for
  "did the VM actually shut down?" checks.

## End-to-end example

Each step is an ordered list item under the candy/box `plan:`; a
probe is a `check:` step, a state-changing action is a `run:` step. Run with
`charly check live arch --filter libvirt`.

```yaml
# Sanity — the domain is up and the agent is reachable.
- check: the session lists the arch domain
  id: libvirt-domains-listed
  libvirt: list
  context: [deploy]
  stdout:
    contains: arch
- check: the domain reports a reachable guest agent
  id: libvirt-agent-reachable
  libvirt: info
  context: [deploy]
  stdout:
    contains: "Agent: true"

# Framebuffer capture (independent of SPICE wire state).
- check: a non-uniform framebuffer screenshot is captured
  id: libvirt-framebuffer
  libvirt:
    method: screenshot
    artifact: /tmp/fb.png
    artifact_not_uniform: true
  context: [deploy]

# Keyboard injection via libvirt (alternate path to the `spice: key` verb).
- run: switch to VT2 via a libvirt key chord
  id: libvirt-send-chord
  libvirt:
    method: send-key
    key: "ctrl+alt+F2"
  context: [deploy]

# QMP escape hatch.
- check: QMP reports the running domain status
  id: libvirt-qmp-status
  libvirt:
    method: qmp
    text: query-status
  context: [deploy]
  stdout:
    contains: running

# qemu-guest-agent (only if the guest has qemu-guest-agent installed).
- check: the guest agent runs uname
  id: libvirt-guest-uname
  libvirt:
    method: guest/exec
    command: uname -a
  context: [deploy]
  stdout:
    contains: Linux

# Transactional testing: snapshot → … → revert → delete.
# The snapshot name rides the SHARED #Op `target:` sibling, not the libvirt map.
- run: snapshot the domain before a destructive step
  id: libvirt-snapshot-create
  libvirt: snapshot/create
  target: pre-exp
  context: [deploy]
- run: revert to the pre-experiment snapshot
  id: libvirt-snapshot-revert
  libvirt: snapshot/revert
  target: pre-exp
  context: [deploy]
- run: delete the snapshot
  id: libvirt-snapshot-delete
  libvirt: snapshot/delete
  target: pre-exp
  context: [deploy]
```

## Remote libvirt (qemu+ssh://)

A `libvirt:` step can target a VM on a remote libvirt host. Set
`CHARLY_LIBVIRT_URI=qemu+ssh://[user@]host/session`: the host-side pre-resolver
opens the SSH connection, discovers the remote virtqemud session socket (via
`id -u`), and forwards it over the SSH channel — so `DomainScreenshot`,
`DomainSendKey`, QMP, etc. all work against the remote hypervisor, with the
artifact written by the `artifact:` modifier locally. Example:

```bash
CHARLY_LIBVIRT_URI=qemu+ssh://o.example.org/session \
  charly check live arch --filter libvirt
```

## Agent prerequisite

`guest/*` methods require `qemu-guest-agent` installed and running in the guest
AND a `<channel type='unix' ... name='org.qemu.guest_agent.0'/>` in the domain
XML. The opencharly layer `qemu-guest-agent` drops this in for bootc VMs;
cloud-image VMs need to add it to `cloud_init.packages:` explicitly.

Use a `libvirt: info` step — if it reports `Agent: false`, the agent is not
reachable.

### Cloud-image VM packages

When a cloud-image VM uses `charly_install.strategy: auto` (the modern
default), the vm deploy plugin's `OpPrepareVenue` (via `kit.EnsureCharlyInGuest`)
scps the **host** `charly` binary into the guest post-boot. The core charly binary is cgo-free for audio — the SPICE audio
channels (the sole opus/portaudio cgo consumers) were dep-shed out of core
into the out-of-tree `candy/plugin-spice`, gated behind `-tags spice_audio`.
`ldd $(command -v charly)` shows no libportaudio/libopus, so the scp'd binary
runs in the guest with NO portaudio/opusfile installed.

Minimum cloud-image package list for full check-live coverage:

```yaml
cloud_init:
  packages:
    - sudo
    - spice-vdagent      # for spice-vdagentd
    - qemu-guest-agent   # for the `libvirt: guest/*` probes
```

## Daemon prerequisite (host side)

The `libvirt:` verb (and every `spice:` check verb) routes through the libvirt
user-session daemon socket. The daemon must be running as a user-service:

```bash
systemctl --user enable --now virtqemud.service     # libvirt ≥ 8 (modular)
# OR (older monolithic):
systemctl --user enable --now libvirtd.service
```

`charly vm create` best-effort starts these units before resolving the VM
backend (see `/charly-vm:vm` "Prereq"). The `charly check run <bed>` path for
VM-targeting beds (e.g. `check-k3s-vm`) invokes the same hook. If the unit
doesn't exist (libvirt not installed), the explicit-backend gate in
`resolveVmBackend()` surfaces a clear error pointing at the remediation.

## Architecture split (vs. the `spice:` verb)

The two VM verbs are single-protocol by design — both served out-of-process by
the `candy/plugin-vm`/`candy/plugin-spice` plugins, neither a host CLI command:

- **`libvirt:`** — libvirt RPC only. Every call goes through libvirtd. Works
  regardless of the VM's graphics protocol. Use when the thing under test is
  "is the VM working?" (framebuffer capture, keyboard injection, snapshots,
  domain state).
- **`spice:`** — SPICE wire only. Proves the SPICE protocol path is alive
  end-to-end. Use when the thing under test is "is SPICE itself healthy?".

For ambiguous display tests, run both and diff: compare `libvirt: screenshot`
against `spice: screenshot` — if both render the same pixels, the SPICE server
and the guest framebuffer agree.

## Implementation pointers

The `libvirt:` verb is served OUT-OF-PROCESS by `candy/plugin-vm` (the
go-libvirt shed moved it out of charly core). The host dispatches it through
the provider registry, passing the resolved per-deploy DOMAIN IDENTITY
(`Runner.vmTargetName()` — the deploy name, not the shared entity, P33) so the verb
addresses the live domain `charly-<deploy>`, correctly distinct per bed.

- `candy/plugin-vm/libvirt_cmd.go` — the libvirt command tree + all method implementations.
- `candy/plugin-vm/libvirt_methods.go` — the method allowlist (op → subcommand-path + positional-args dispatch data).
- `candy/plugin-vm/libvirt_ops.go` — shared helpers (screenshot PPM→PNG decode, key-name → Linux keycode map).
- `candy/plugin-vm/libvirt_guest_agent.go` — typed client over `QEMUDomainAgentCommand` with methods for every QGA command in use.
- `candy/plugin-vm/vm_target.go` — VM target resolution; `VmTarget.XML` gives you the live `libvirtxml.Domain` for fast field lookups.

## Dependencies

These live in `candy/plugin-vm` (the out-of-process plugin), NOT charly core:

- `github.com/digitalocean/go-libvirt` — pure-Go libvirt RPC client.
- `libvirt.org/go/libvirtxml` — typed domain XML parsing/generation.
- The `libvirt` Arch package (libvirtd, session socket) is already a hard dep of the `opencharly-git` PKGBUILD.

## Cross-References

- `/charly-check:check` — parent router; the `libvirt:` verb catalog entry, the artifact-validation modifiers, and `charly check live <vm> --filter libvirt`.
- `/charly-check:spice` — the sibling `spice:` SPICE-wire check verb, also served out-of-process by `candy/plugin-vm`/`candy/plugin-spice`.
- `/charly-internals:plugin` — the out-of-process provider model that serves `libvirt` (`candy/plugin-vm`).
- `/charly-vm:vm` — the `charly vm` VM lifecycle command family (create/start/stop/destroy/ssh/console/gpu) — separate from this introspection verb.

## When to Use This Skill

**MUST be invoked** before any work involving: the `libvirt:` check verb,
libvirt RPC-based VM inspection/management, qemu-guest-agent probing, VM
snapshots, domain event watching, or any VM-introspection surface beyond what
`charly vm` (lifecycle) provides.
