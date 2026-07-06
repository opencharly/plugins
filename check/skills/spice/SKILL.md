---
name: spice
description: the `spice:` SPICE-wire check verb for VMs — handshake, native-SPICE display screenshots, and input injection, served out-of-process by candy/plugin-spice (the vendored Shells-com/spice library).
allowed-tools: Bash, Read
---

# SPICE — VM display-protocol check verb

## Overview

`spice:` is a DECLARATIVE check verb — authored as `spice: <method>` inside a
candy/box plan `check:`/`run:` step. **There is no host `charly check spice`
command.** The SPICE-wire implementation (and the upstream SPICE client
library + its cgo opus/portaudio audio transitives) was dep-shed into the
out-of-tree `candy/plugin-spice` plugin module; at check time the host
dispatches `spice:` through the provider registry to that out-of-process
plugin (the same path a bed's checks take via `charly check live` / `charly
check run`). This mirrors the `adb:` / `appium:` / `kube:` externalizations
(see charly/check_cmd.go).

The verb *proves* the SPICE server is speaking the protocol correctly on the
wire — not just that the TCP port is open: main-channel handshake, auth,
channel enumeration, native display-channel image decode, and input injection.
VM-only — it needs a running libvirt VM that exposes a `<graphics type='spice'>`
device.

### The host pre-resolves the endpoint; the plugin speaks the wire

charly core owns NO go-libvirt. The host (`preresolveSpiceEndpoint`,
charly/spice_preresolve.go) DELEGATES the vm.yml → libvirt-domain → live-XML →
`<graphics type='spice'>` resolution to the out-of-process vm plugin
(`invokeVmPlugin("resolve-spice", …)` → candy/plugin-vm's `ResolveVmTarget` /
`SpiceEndpoint`, where the go-libvirt deps live), passing the resolved VM-entity
name (`Runner.vmTargetName()`) as the domain target. It opens any qemu+ssh:// side
tunnel itself from the returned endpoint and hands the spice plugin a plain
DIALABLE endpoint via the CheckEnv. The spice plugin just dials it and runs the
method.

## Authoring the `spice:` verb in a plan step

The verb is one inline Op carried by a step — an ordered list item under the
candy/box `plan:` (a display/handshake probe is a `check:` step; an input action
that changes guest state is a `run:` step). The method name is the scalar value for
a bare-method step (`spice: status`), or the `method:` key of the `spice:` map when
the step carries spice-exclusive fields — those live INSIDE the `spice:` map:

| Method | Declarative form | Map fields | Description |
|---|---|---|---|
| `status` | `spice: status` | — | handshake + channel enumeration (first line `SPICE:     ok`) |
| `screenshot` | `spice: {method: screenshot, artifact: …}` | `artifact:` | native SPICE display-channel decode → PNG |
| `cursor` | `spice: {method: cursor, artifact: …}` | `artifact:` | capture cursor bitmap + position → PNG |
| `click` | `spice: {method: click, x: …, y: …}` | `x:`, `y:`, `button:` | mouse press/release via the inputs channel |
| `mouse` | `spice: {method: mouse, x: …, y: …}` | `x:`, `y:` | pointer move (no click) |
| `type` | `spice: {method: type, text: …}` | `text:` | type text as PC-AT scancodes |
| `key` | `spice: {method: key, key: …}` | `key:` | press one named key (Return, Escape, F2, …) |

The artifact validators (`artifact_min_bytes:`, `artifact_min_dimensions:`,
`artifact_not_uniform:`) are spice-exclusive too, so they live inside the `spice:`
map; only the shared matchers (`stdout:`, `stderr:`, `exit_status:`) and
`context:`/`timeout:`/`id:` stay siblings of the `spice:` key. **`context: [deploy]`**
— the verb needs a running VM; under `charly check box` (no running VM) it
skips, and a SPICE-less deployment (e.g. a GPU desktop with no `<graphics
type='spice'>` device) is reported N/A SKIP.

The method-name enum (`status`/`screenshot`/`cursor`/`click`/`mouse`/`type`/`key`)
and every spice modifier live in the plugin's OWN input schema
(`candy/plugin-spice/schema/spice.cue`, `#SpiceInput`), served over the Describe
channel and spliced onto the base for validation — so authoring is UNCHANGED from a
built-in verb (`spice: status`, not `plugin: spice`); the internal
plugin/plugin_input wire envelope the sugar desugars to is never authored.

Example — each step is an ordered list item under the candy/box `plan:`:

```yaml
- check: the SPICE server completes the handshake and enumerates channels
  id: spice-handshake
  spice: status
  context: [deploy]
  stdout:
    - contains: ok
    - contains: "inputs:    ready"
- check: the SPICE display channel decodes a non-uniform framebuffer
  id: desktop-rendered
  spice:
    method: screenshot
    artifact: /tmp/spice-shot.png
    artifact_not_uniform: true
  context: [deploy]
```

Input injection is authored as `run:` steps (each one mutates guest state) — a
console login sequence walks the form with `spice: key` / `spice: type` steps:

```yaml
- run: type the username and password at the console
  id: drive-login
  spice:
    method: key
    key: return
  context: [deploy]
# … followed by `spice: {method: type, text: arch}` and `spice: {method: key, key: tab}`
# steps to walk the login form.
```

## Remote libvirt (qemu+ssh://)

A `spice:` step can target a VM on a remote libvirt host. Set
`CHARLY_LIBVIRT_URI=qemu+ssh://[user@]host/session` (the former `--uri` flag
carried this same env): the host-side pre-resolver runs locally, discovers the
remote SPICE endpoint, and opens the side tunnel transparently — libvirt RPC
rides the SSH control channel; the SPICE display channel gets a dedicated
forward.

- For VMs that declare `<listen type='socket'/>` (the arch default after the
  socket-listen cutover), the host forwards the UNIX socket.
- For TCP-listener VMs, the host opens a `127.0.0.1:<random>` forward.

GUI clients (virt-manager, `remote-viewer --connect qemu+ssh://…`) don't need
any charly involvement for socket listeners — they auto-forward via libvirt
RPC fd-passing. See `/charly-vm:arch` "Connecting from a remote workstation"
for the complete story.

## What it does (and doesn't)

- **Speaks SPICE on the wire.** Main channel handshake, auth (None or
  SPICE_TICKET), channel enumeration (Display/Inputs/Cursor/Playback/
  Record/Webdav), display channel with native QUIC/GLZ/LZ/LZ4 image
  decode, input channel for key/mouse events.
- **Endpoint resolved host-side.** The host loads vm.yml, finds the running
  libvirt domain, parses live XML via `libvirtxml.Domain`, and extracts the
  SPICE host/port/passwd from the `<graphics type='spice'>` element (honoring
  autoport='yes') before handing the plugin a dialable endpoint. The operator
  escape-hatches the former CLI exposed (`--address`, `--socket`, `--password`)
  are NOT part of the declarative verb — the endpoint comes from the bed's VM
  context.
- **Native SPICE screenshot.** `spice: screenshot` is a native SPICE
  display-channel decode (NOT libvirt `DomainScreenshot`) — it proves the SPICE
  display path renders pixels end-to-end. `type`/`key` emit PC-AT scancodes
  (the friendly-keyname → scancode table lives in the plugin).
- **Not implemented.** Audio playback/record (no user story) — the plugin is
  built WITHOUT `-tags spice_audio`, so the upstream library's cgo
  opus/portaudio audio channels are not linked. Complex agent-channel
  operations (clipboard, resolution change); the upstream library exposes them
  but the verb doesn't wrap them yet — use the `libvirt:` verb (`libvirt:
  passwd`, `libvirt: guest/exec`) for the corresponding management ops.

## Architecture split (vs. the `libvirt:` verb)

The two verbs are single-protocol by design:

- **`spice:`** — every byte flows through the SPICE wire. Use when the thing
  under test is "is SPICE itself healthy?".
- **`libvirt:`** — every call goes through libvirtd RPC. Use when the thing
  under test is "is the VM working?" (framebuffer capture, keyboard injection,
  snapshots, domain state). The `libvirt:` verb is likewise a declarative check
  verb served out-of-process — by `candy/plugin-vm` (see `/charly-check:libvirt`).

For input testing, prefer `spice: type`/`key`/`click` to prove the SPICE wire
delivers input to the guest. For display testing, compare `spice: screenshot`
against `libvirt: screenshot` — if both render the same pixels, the SPICE
server + the guest framebuffer agree.

## Implementation

The `spice:` verb and its SPICE-wire client live in the out-of-tree
`candy/plugin-spice` plugin module (an external-charly-verb plugin), NOT in
charly's core (which carries no SPICE library and no opus/portaudio cgo deps).

- `candy/plugin-spice/provider.go` — the out-of-process verb provider: it
  dials the host-pre-resolved endpoint, dispatches the method, then
  self-evaluates the stdout/stderr/exit_status matchers + the artifact
  validators itself.
- `candy/plugin-spice/session.go` / `methods.go` — the connection wrapper over
  the SPICE library's `Connector`/`Driver` interfaces and the per-method
  implementations.
- `candy/plugin-spice/third_party/spice` — the vendored Shells-com/spice
  library, built without the audio tag (`ch-audio-stub.go`).
- `candy/plugin-spice/schema/spice.cue` — the plugin's served CUE schema: the
  `#SpiceInput` def carries the method enum + every spice modifier, served over
  the Describe channel and spliced onto the base for authored-input validation.

Host side:

- `charly/spice_preresolve.go` — `preresolveSpiceEndpoint`: delegates vm.yml →
  libvirt domain → live XML → SPICE endpoint to the vm plugin, opens any
  qemu+ssh:// side tunnel, and hands the spice plugin a dialable `SpiceEnv` via
  the CheckEnv. Stays in core (it owns no go-libvirt).
- `candy/plugin-vm/vm_target.go` — the OUT-OF-PROCESS VM target resolution
  (`ResolveVmTarget` / `SpiceEndpoint`, go-libvirt); `VmTarget.XML` gives the live
  `libvirtxml.Domain`. The host reaches it via `invokeVmPlugin("resolve-spice", …)`,
  passing `Runner.vmTargetName()` (the resolved VM-entity name, not the deploy name).
- The registry dispatch: `providerRegistry.ResolveVerb("spice")` → the
  out-of-process `grpcProvider` → `invokeVerbProvider`, which hands the plugin
  the full `#Op` as params after the host pre-resolves the endpoint.

## Dependencies

These now live in `candy/plugin-spice`, NOT in charly's core:

- `github.com/Shells-com/spice` (MIT) — SPICE client library, vendored under
  `third_party/spice`.
- `github.com/hraban/opus` + `github.com/gordonklaus/portaudio` — cgo audio
  transitives, indirect and NOT linked (the plugin is built without
  `-tags spice_audio`).

The VM target resolution (go-libvirt / `libvirtxml`) runs OUT-OF-PROCESS in
`candy/plugin-vm/vm_target.go` — the host reaches it via
`invokeVmPlugin("resolve-spice", …)`, not a direct core call, and passes the
resolved VM-entity name (`Runner.vmTargetName()`) so the plugin addresses the live
domain `charly-<vm-entity>` even when the deploy/bed name differs.

## Related skills

- `/charly-check:libvirt` — the sibling declarative `libvirt:` check verb,
  served out-of-process by `candy/plugin-vm` (libvirt RPC: framebuffer
  screenshot, send-key, QMP, snapshots, guest agent).
- `/charly-check:check` — the unified check system and the Op (a plan step)
  that holds every verb discriminator + modifier.
- `/charly-vm:arch` — the arch VM that ships SPICE by default; "Connecting from
  a remote workstation".
- `/charly-internals:plugin` — the external-charly-verb plugin model the spice
  verb follows.

## When to Use This Skill

**MUST be invoked** for any task involving the `spice:` declarative check verb,
SPICE protocol debugging, or proving a libvirt VM's SPICE display path is alive
end-to-end. Invoke this skill BEFORE reading the plugin's Go source.
