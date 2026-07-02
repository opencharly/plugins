---
name: ssh
description: Generic SSH support for charly — `--host <alias>` re-execs any command on a remote machine; `charly ssh tunnel` exposes remote SPICE/VNC endpoints on the local host for external GUI apps.
allowed-tools: Bash, Read
---

MUST be invoked before any work involving: `charly --host <alias|target>`
remote execution, `charly ssh tunnel` port forwarding for external SPICE/VNC
viewers, or managing host aliases via `charly settings set hosts.<alias>`.

## Two orthogonal surfaces

### 1. `charly --host <alias>` — re-exec any charly command on a remote machine

Set `--host` (or `CHARLY_HOST`) at the **top level** of any `charly` invocation.
`charly` shells out to the system `ssh` binary, runs `charly <rest of argv>` on
the remote host, and streams stdin/stdout/stderr through. Exit code
propagates.

```bash
# Alias setup (once per workstation):
charly settings set hosts.o o.example.org
charly settings set hosts.prod admin@prod.example.com:2222

# Any charly verb works:
charly --host o status
charly --host o start openclaw
charly --host o vm list
charly --host o deploy add host fedora-coder
charly --host o test libvirt info arch
charly --host o test libvirt screenshot arch - > /tmp/local.png   # stdout pipes back
```

**LocalOnly commands are NOT re-execed**, even when `--host` is set:
`charly settings …`, `charly version`, `charly ssh tunnel …`. These manage the local
workstation (settings file, CLI version, local tunnel listener) and
would be meaningless on the remote host.

**Transport:** system `ssh` binary via `os/exec`, so `~/.ssh/config`,
agent forwarding, and ControlMaster all work transparently. If your
target needs a specific key, set it in `~/.ssh/config` — `charly` stays out
of SSH authentication.

**Client-only flags stripped** before re-exec: `--host`, `--dir` / `-C`,
`--repo`. These are workstation-local concerns and must not be
forwarded to the remote side.

### 2. `charly ssh tunnel` — expose a remote VM's display for external GUI apps

For apps that aren't `charly` (virt-viewer, remote-viewer with a bare URL,
TigerVNC, Spicy), open an SSH-forwarded local endpoint:

```bash
charly ssh tunnel spice <vm> [--uri qemu+ssh://user@host/session] [--tcp]
charly ssh tunnel vnc   <vm> [--uri qemu+ssh://user@host/session] [--tcp]
```

Default mode preserves the wire format: UNIX socket in, UNIX socket out
(local path under `/tmp/charly-tunnel-<id>.sock`). `--tcp` forces a
127.0.0.1:<random> TCP listener for clients that don't understand
`spice+unix://` / `vnc+unix://`.

```
$ charly ssh tunnel spice arch --uri qemu+ssh://o.example.org/session
spice tunnel: spice+unix:///tmp/charly-tunnel-8e4c.sock
Connect with: remote-viewer spice+unix:///tmp/charly-tunnel-8e4c.sock
Press Ctrl-C to close the tunnel.
```

Blocks until SIGINT/SIGTERM; closes listener + SSH client cleanly on
exit.

**Not needed for virt-manager or `remote-viewer --connect qemu+ssh://`**
— those auto-forward UNIX-socket listeners through libvirt's RPC
fd-passing, with zero charly involvement. See `/charly-vm:arch`.

## Alias management

| Command | Effect |
|---|---|
| `charly settings set hosts.<alias> <ssh-target>` | create/update alias |
| `charly settings get hosts.<alias>` | print resolved target |
| `charly settings reset hosts.<alias>` | delete alias |
| `charly settings list` | show all settings including host_aliases map |

`<ssh-target>` forms: `host`, `user@host`, `user@host:port`. When
resolving, plain words that look like aliases (no `@`, no `.`) are
looked up in `hosts.*`; anything else is treated as a raw ssh target
and passed through.

## When NOT to use `--host`

- When you want artifacts (screenshots, recordings) to land in the local
  filesystem → use the declarative `libvirt:`/`vnc:`/`spice:` check verbs against
  the vm target with `CHARLY_LIBVIRT_URI=qemu+ssh://…` set instead; it runs
  charly locally and forwards the display channel over SSH.
- When `charly` isn't installed on the remote machine → set
  `CHARLY_LIBVIRT_URI` or use `charly ssh tunnel`.

## Cross-References

- `/charly-vm:arch` — "Connecting from a remote workstation" —
  the canonical worked example across all three paths.
- `/charly-build:settings` — `hosts.<alias>` key schema.
- `/charly-check:spice` — the declarative `spice:` check verb; the host resolves the VM's SPICE endpoint (honoring `CHARLY_LIBVIRT_URI` for a remote hypervisor).
- `/charly-check:libvirt` — the declarative `libvirt:` check verb served out-of-process by candy/plugin-vm; honors `CHARLY_LIBVIRT_URI` for a remote hypervisor.
- `/charly-check:vnc` — the declarative `vnc:` check verb (served out-of-process by candy/plugin-vnc); the host pre-resolves the RFB endpoint for pod AND vm targets (a VM's libvirt VNC via bridge/tunnel).
