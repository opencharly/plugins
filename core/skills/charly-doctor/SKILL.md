---
name: charly-doctor
description: |
  Host dependency checker and hardware detector for the `charly doctor` CLI verb.
  Use when diagnosing host setup, checking dependencies, or verifying GPU detection.
  Named `charly-doctor` (not `doctor`) to disambiguate from Claude Code's built-in `/doctor` slash command.
---

# Doctor - Host Dependency Check

## Overview

`charly doctor` checks all host dependencies grouped by feature area, probes for GPU and device hardware, and reports a summary. Use it to diagnose missing tools, verify GPU setup, or check if a host is ready for charly operations.

`charly doctor` is a **compiled-in COMMAND-class plugin** (`candy/plugin-doctor`, `command:doctor`) — one of the externalized welded commands, following the same doctrine as `command:clean` and `command:settings`. The user-facing command is unchanged. The plugin OWNS the whole host-dependency report: the check list, the group orchestration, the pass/warn/fail verdicts, the human + JSON formatting, the exit code, AND the pure host ops it runs itself (binary probes via `exec.LookPath`, file reads like `/etc/fuse.conf` and the `~/.config/charly/config.yml` permissions `os.Stat`). `candy/plugin-doctor/command.go` holds `runDoctorCLI` plus every check/format function and the `DoctorCheckResult`/`CheckGroup`/`DoctorOutput` report types. The plugin reaches back into core ONLY for the genuine host-hardware subsystem it cannot hold itself — the GPU/VFIO/device detection primitives (the C11 shims `DetectGPU`/`DetectAMDGPU`/`DetectHostDevices`/`DetectVFIO`/`VfioGroupAccessible`/`MemlockLimitBytes`/`detectAMDGFXVersion`, which STAY core because deploy/vm are multi-callers — and since C11 resolve+Invoke the compiled-in `candy/plugin-gpu`, see `/charly-internals:go` `gpu_shim.go`), the credential-store health (`credentialHealth`, verb:credential, which lazy-connects host-side), and the core install-hint / device-description data tables — all over ONE generic **"hostprobe"** `HostBuild` seam (`charly/host_build_hostprobe.go`, registered via `registerHostBuilder`; `spec.HostProbeRequest` → `spec.HostProbeReply`, CUE-sourced at `sdk/schema/doctor.cue` and generated into `spec/cue_types_gen.go`, which also owns the moved `spec.CredentialHealth`). `HostProbeReply.GroupAccessible` is string-keyed (`map[string]bool`, the decimal group-number as its own key — CUE has no int-keyed-map construct; `encoding/json` already renders a `map[int]bool`'s keys as decimal strings on the wire, so this is a pure representation fix, zero wire-format change). The seam returns RAW FACTS ONLY — zero report or verdict logic lives in core. doctor is compiled-in (listed in `charly/charly.yml` `compiled_plugins`) because its `Invoke(OpRun)` needs the in-proc reverse channel to call `HostBuild("hostprobe")`; dispatch is `dispatchInProcCommand` → `Invoke(OpRun)` → `runDoctorCLI`. doctor's seam exists because its inputs are heterogeneous host-hardware facts plus core data tables, so a single generic host action noun collects them once.

## Usage

```bash
charly doctor              # Human-readable output
charly doctor --json       # Machine-readable JSON (DoctorOutput struct)
```

## Check Groups

Dependencies are organized into groups. Required groups cause a non-zero exit if all checks fail.

### Container Engine (required, OR-logic)

At least one must be installed:
- `docker`
- `podman`

### Build Infrastructure

- `go` — required to build charly from source
- `git`
- `docker buildx` — only checked if docker is available

### Service Management (quadlet mode)

- `systemctl`
- `podman` (for quadlet)

### Virtual Machines

- `qemu-system-x86_64` (or arch-specific variant)
- `qemu-img`
- `virtiofsd` — checks PATH + `/usr/lib/virtiofsd` + `/usr/libexec/virtiofsd`
- `virsh`
- `ssh`
- libvirt session socket

### Encrypted Storage

- `gocryptfs`
- `fusermount3`
- `systemd-ask-password`

### Secret Storage

- **Secret backend availability** — keyring or config. Reports which backend is active and whether it probed healthy.
- **Config file permissions** — warns if `~/.config/charly/config.yml` is not `0600`.
- **Plaintext credential count** — warns if `> 0` plaintext entries are in `config.yml` (suggests `charly secrets migrate-secrets`).
- **Secret Service collections** — iterates the Secret Service provider's collections and reads the `Label` property on each. A *broken* collection is one whose `org.freedesktop.DBus.Properties.Get` returns `NoSuchObject` or a DBus I/O error — the hallmark of KeePassXC FdoSecrets stubs or a corrupt keyring. Status is `CheckOK` when all collections respond, `CheckWarning` when any are broken (charly iterates past them automatically — see `/charly-automation:enc`). The `Detail` field names the broken path(s) so the user can act on them (KeePassXC → Tools → Settings → Secret Service Integration → Exposed Databases).
- **Keyring index consistency** — cross-checks the `keyring_keys` shadow index in `config.yml` against the live Secret Service via `findItemAnyCollection`. For every indexed `service/key` entry, looks it up through the iteration-capable read path. Status is `CheckOK` if `N/N` indexed keys resolve, `CheckWarning` with the stale entries listed otherwise. Remediation hint: `charly secrets set <service> <key>` to re-store, or prune the shadow index.

### Tunnels

- `tailscale`
- `cloudflared`

### Merge & Registry

- `skopeo`

### Shell & TTY

- `script`

### Podman Machine (conditional)

Only shown if podman is installed:
- `gvproxy` — checks PATH + `/usr/libexec/podman/gvproxy` + `/usr/lib/podman/gvproxy`

## Hardware Detection

Probes GPU and device hardware, reports what flags containers will receive:

| Device | Description | Container flag |
|--------|-------------|---------------|
| NVIDIA GPU | CUDA-capable GPU | `--gpus all` or CDI device |
| AMD GPU | ROCm compute | `--group-add keep-groups` |
| `/dev/dri/renderD*` | GPU render node | `--device /dev/dri/renderD128` |
| `/dev/kfd` | AMD Kernel Fusion Driver | `--device /dev/kfd` |
| `/dev/kvm` | KVM virtualization | `--device /dev/kvm` |
| `/dev/vhost-net` | vhost network acceleration | `--device /dev/vhost-net` |
| `/dev/vhost-vsock` | VM socket communication | `--device /dev/vhost-vsock` |
| `/dev/fuse` | FUSE filesystem | `--device /dev/fuse` |
| `/dev/net/tun` | TUN/TAP network device | `--device /dev/net/tun` |
| `/dev/hwrng` | Hardware RNG | `--device /dev/hwrng` |

AMD GPU detection also reports the GFX version (e.g., `gfx 11.0.0`) from KFD topology nodes and sets `HSA_OVERRIDE_GFX_VERSION` accordingly.

**DRINODE auto-detection:** `charly` automatically finds the first `/dev/dri/renderD*` device and injects it as `DRINODE` and `DRI_NODE` environment variables into `charly config`, `charly start`, and `charly shell` sessions. This ensures GPU render node selection is consistent across all operations without manual configuration. Since C11 the detection runs in `candy/plugin-gpu` (the `DetectHostDevices` shim resolves+Invokes `verb:gpu`; `DetectedDevices.RenderNode` is the picked node, the type living in package spec); the injection stays centralized in `appendAutoDetectedEnv()` — relocated from `charly/devices.go` to `candy/plugin-deploy-pod/config_setup_helpers.go` in the 2026-07-22 dead-code-radical-removal batch (the charly-core copy was unreached residue once the plugin took over the real `charly config`/`start`/`shell` call sites).

**Why centralized:** DRINODE injection lives in the single `appendAutoDetectedEnv()` helper (now in `candy/plugin-deploy-pod`) so `/charly-core:charly-config`, `/charly-core:start`, and `/charly-core:shell` all produce the identical env set — a fix applied to one reaches all three. `/charly-distros:nvidia` and `/charly-distros:rocm` ship no hardcoded render nodes in their charly.yml; they rely on this detection instead.

**Disabling auto-detection:** Pass `--no-autodetect` to `charly config` to skip all of DRINODE, DRI_NODE, and HSA_OVERRIDE_GFX_VERSION injection. Useful when you want to set these values explicitly or test a candy without host device dependence. See `/charly-core:charly-config` flag table.

## Output Format

Human-readable output uses symbols:
- `[+]` — installed / detected
- `[-]` — missing
- `[!]` — warning (installed but with caveats)
- `[ ]` — not present (hardware, neutral)

Each check shows the binary path and version when available, or an install hint when missing. Install hints are distro-aware (suggests `pacman`, `dnf`, `apt` as appropriate).

## JSON Output

`charly doctor --json` emits a `DoctorOutput` struct with:
- `system` — detected distro info
- `groups` — all check groups with individual results
- `hardware` — GPU flags, device list, container flags
- `summary` — counts of installed, missing, warnings, devices

## Cross-References

- `/charly-automation:udev` — install udev rules for GPU device access
- `/charly-core:charly-config` — `engine.build`, `engine.run`, `secret_backend` settings, `--no-autodetect` flag, DRINODE injection via `appendAutoDetectedEnv()`
- `/charly-automation:enc` — credential lookup path behind the Secret Service collection + keyring-index checks; iteration-capable ssClient; broken-collection troubleshooting
- `/charly-build:secrets` — `charly secrets set/list/prune` commands referenced by the keyring-index remediation hint
- `/charly-build:settings` — `keyring_collection_label`, `secret_backend`, and other runtime config keys surfaced by the Secret Storage checks
- `/charly-core:shell` — auto-detected env vars (DRINODE, DRI_NODE, HSA_OVERRIDE_GFX_VERSION) injected via the same `appendAutoDetectedEnv()` path
- `/charly-core:start` — same auto-injection path at service-start time
- `/charly-distros:nvidia` — NVIDIA GPU runtime support + DRINODE Auto-Injection section
- `/charly-distros:rocm` — AMD ROCm runtime support + DRINODE/HSA_OVERRIDE_GFX_VERSION auto-detect table
- `/charly-selkies:selkies` — Primary consumer of DRINODE for VAAPI H.264 encode

## Source

`candy/plugin-doctor/{command.go,provider.go,plugin.go}` — the compiled-in `command:doctor` plugin that OWNS the whole report: `command.go` holds `runDoctorCLI`, the check/format functions, and the `DoctorCheckResult`/`CheckGroup`/`DoctorOutput` types; `provider.go` is the `Invoke(OpRun)` surface the compiled-in dispatch calls; `plugin.go` carries `NewMeta`/`NewProvider`/`CliMain`. The genuine host subsystem stays core and is reached over the generic "hostprobe" `HostBuild` seam: `charly/host_build_hostprobe.go` (registered via `registerHostBuilder`, returns raw facts only) with the wire types CUE-sourced at `sdk/schema/doctor.cue` (`HostProbeRequest`/`HostProbeReply`/`CredentialHealth`). The GPU/VFIO/device detection shims (`charly/gpu_shim.go`, serving `candy/plugin-gpu`) and `credentialHealth` (`charly/credential_plugin.go`, verb:credential) stay core as multi-callers with the deploy/vm paths; the install-hint / device-description data tables live in `charly/charly.yml`.

## When to Use This Skill

Use when the user asks about:
- Host dependency checks or setup verification
- GPU hardware detection
- Whether a system is ready for charly operations
- The `charly doctor` command
