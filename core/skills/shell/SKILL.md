---
name: shell
description: |
  MUST be invoked before any work involving: charly shell command, interactive shells, command execution in containers, workspace mounts, TTY allocation, or port relay.
---

# Shell - Shell & Execution

## Overview

`charly shell` runs an interactive shell or executes commands inside containers. Supports workspace mounting, device auto-detection, environment injection, and TTY allocation for automation tools.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Interactive shell | `charly shell <image>` | Bash shell in container |
| Bind workspace | `charly shell <image> --bind workspace=~/project` | Mount host dir as workspace volume |
| Volume config | `charly shell <image> -v name:type[:path]` | Configure volume backing (volume\|bind\|encrypted) |
| Run command | `charly shell <image> -c "cmd"` | Execute command and exit |
| Force TTY | `charly shell <image> --tty -c "cmd"` | PTY allocation for automation |
| Specific version | `charly shell <image> --tag v1.0.0` | Use specific image tag |
| No devices | `charly shell <image> --no-autodetect` | Disable device auto-detection |
| Set env var | `charly shell <image> -e KEY=VALUE` | Inject environment variable |
| Load env file | `charly shell <image> --env-file .env` | Load env from file |
| Named instance | `charly shell <image> -i runner-1` | Use named instance |
| Force build | `charly shell <image> --build` | Build locally before running |

**Note:** `charly shell` does not accept remote refs (`@github.com/...`). Remote
refs are handled exclusively by `charly box pull` (build-mode). Pull first,
then `charly shell <image-name>` works via labels. See `/charly-build:pull`.

## How It Works

1. Resolves image from OCI labels via `ExtractMetadata` (never `charly.yml`)
2. Applies `charly.yml` overlay (volumes, env, sidecars, tunnel)
3. Ensures image exists in run engine (transfers from build engine if needed)
4. Resolves volumes (with deploy-time backing), ports, security, environment
5. If container is already running: `<engine> exec` into it
6. If not running: `<engine> run` with full configuration

If the image isn't in local storage, `ExtractMetadata`/`EnsureImage` return
`ErrImageNotLocal` and the CLI surfaces:
```
Error: image "X" is not available locally.
       Run 'charly box pull X' to fetch it first
```
See `/charly-build:pull` for the full sentinel pattern.

## Volume Binding

```bash
charly shell <image> --bind workspace=~/project  # Bind ~/project as workspace volume
charly shell <image> --bind workspace=.          # Bind PWD as workspace volume
charly shell <image>                             # No host mount (named volume)
```

The `--bind` flag overrides volume backing for the session. For finer control, use `-v name:type[:path]` where type is `volume`, `bind`, or `encrypted`. The container working directory is `~/workspace` (resolved from the `workspace` volume). If a `.env` file exists in the bound directory, it is auto-loaded.

## --tty Flag

Forces TTY allocation even when stdout is not a terminal. Uses `script(1)` from util-linux to provide a real PTY.

```bash
# Without --tty: "not a tty" errors from interactive commands
charly shell my-app -c "interactive-cli auth login"       # fails in CI/automation

# With --tty: script(1) wraps the command in a PTY
charly shell my-app --tty -c "interactive-cli auth login"  # works everywhere
```

Essential for automation tools (Claude Code, CI runners) where stdout is a pipe, not a terminal. Many interactive CLI commands (OAuth flows, prompts) require a TTY.

Works for both new containers (`<engine> run`) and exec into running containers (`<engine> exec`).

## Exec Into Running Containers

When `charly shell` detects the container is already running (via `<engine> inspect`), it uses `<engine> exec` instead of `<engine> run`. The same flags work:

```bash
charly start my-app                            # Start background service
charly shell my-app -c "cat /etc/hostname"     # Exec into running container
charly shell my-app                            # Interactive shell in running container
```

## Port Relay

The `port_relay` field in charly.yml solves the problem of services that bind only to 127.0.0.1 inside the container (e.g., Chrome 146+ DevTools). Container port mappings only forward to interfaces visible from outside, so a loopback-only service is unreachable from the host.

```yaml
# In charly.yml:
port_relay:
  - 9222
```

How it works:
- socat binds to `eth0:<port>` and forwards to `127.0.0.1:<port>`
- An init system service is auto-generated (via the embedded `init:` vocabulary's `<name>.relay_template`) with priority 1 (starts before other services)
- The socat candy is automatically added as a dependency

This makes loopback-only services accessible through normal podman/docker port mappings and `tailscale serve`.

Source: `sdk/deploykit/routes.go` (`GenerateTraefikRoutes` / `EmitTraefikRouteStage`, relocated from `charly/generate.go` in #67), `charly/layers.go` (`PortRelayYAML`).

## Device Auto-Detection

By default, `charly shell` auto-detects available host devices and passes them through. Use `--no-autodetect` to disable.

**Auto-detected devices:**
- NVIDIA GPU (via `nvidia-smi`) -- `--gpus all` (Docker) or `--device nvidia.com/gpu=all` (Podman)
- AMD GPU (via sysfs `amdgpu` driver) -- `--device /dev/kfd` + `--group-add keep-groups` + auto-detected `HSA_OVERRIDE_GFX_VERSION` from KFD topology
- `/dev/dri/renderD*` -- GPU render nodes
- `/dev/kfd` -- AMD Kernel Fusion Driver (ROCm compute)
- `/dev/kvm` -- KVM virtualization
- `/dev/vhost-net`, `/dev/vhost-vsock` -- virtio networking
- `/dev/fuse` -- FUSE filesystem
- `/dev/net/tun` -- TUN/TAP networking
- `/dev/hwrng` -- hardware RNG

When an AMD GPU is detected, `keep-groups` is auto-added to preserve host supplementary groups (video, render) inside the container, and `HSA_OVERRIDE_GFX_VERSION` is auto-set from the GPU's KFD topology (e.g., `10.3.0` for RDNA2). Additionally, the first detected `/dev/dri/renderD*` device is auto-injected as `DRINODE` and `DRI_NODE` env vars (used by selkies for VAAPI encoding). All auto-detected env vars can be overridden via `-e`.

**Shared code path:** `charly shell` calls `appendAutoDetectedEnv()` in `charly/devices.go` — the same function used by `charly config` and `charly start`. That means the three commands produce an identical env set on every run, eliminating drift that used to exist when DRINODE injection was scattered across 10 different call sites before commit `8f6f322`. See `/charly-core:charly-doctor` (Hardware Detection) for the probe side, `/charly-distros:nvidia` (DRINODE Auto-Injection) for the NVIDIA consumer, and `/charly-distros:rocm` (Runtime Environment) for the AMD consumer.

Source: `charly/devices.go` (`appendAutoDetectedEnv`, the env/group helpers) + `charly/gpu_shim.go` (the `DetectHostDevices`/`DetectGPU`/`DetectAMDGPU` shims, which since C11 resolve+Invoke the compiled-in `candy/plugin-gpu`).

## Environment Variables

Runtime environment variables are injected from multiple sources. Resolution priority (last wins for duplicate keys):

1. **Deploy config `env:`** (charly.yml / charly.yml) -- lowest priority
2. **Deploy config `env_file:`** (charly.yml / charly.yml)
3. **Workspace `.env`** file -- auto-loaded from `-w` directory
4. **CLI `--env-file`** flag
5. **CLI `-e`** flags -- highest priority

```bash
charly shell <image> -e DB_HOST=localhost -e DB_PORT=5432
charly shell <image> --env-file production.env
```

Kong `sep:"none"` on `-e` means commas in values are safe (e.g., `NO_PROXY=localhost,127.0.0.1`).

`.env` file format (Docker-compatible): `KEY=VALUE`, `KEY="VALUE"`, `KEY='VALUE'`, `KEY` (inherits from host), `#` comments, blank lines ignored.

Source: `charly/envfile.go` (`ParseEnvFile`, `ResolveEnvVars`, `LoadWorkspaceEnv`).

## Remote Image References

`charly shell` **does not** accept `@github.com/...` remote refs. Pre-refactor
versions did; post-refactor, deploy-mode commands read only from local OCI
labels, so remote refs are rejected with a redirect:

```
Error: remote refs are not accepted here;
       run 'charly box pull @github.com/org/repo/my-app' first,
       then 'charly shell my-app'
```

To run a shell on a remote image, pull it first (via `charly box pull`) and
then invoke `charly shell <short-name>`. See `/charly-build:pull` for the full remote-ref
workflow.

## Cross-Engine Image Transfer

When `engine.build` differs from `engine.run`, images are automatically transferred between engines on demand via `<src> save | <dst> load`.

Source: `charly/transfer.go`.

## Container Networking

All containers are connected to a shared `charly` network by default, enabling inter-container DNS resolution by container name. Override with `network: host` in charly.yml.

Source: `charly/network.go`.

## `charly cmd` vs `charly shell -c`

`charly cmd <image> "command"` is a dedicated single-command tool for **running containers only**. Key differences from `charly shell -c`:

| | `charly cmd` | `charly shell -c` |
|---|---------|--------------|
| Container state | Running only | Running or starts new |
| Notification | Yes (`--[no-]notify`) | No |
| Process model | `exec.Command` (returns) | `syscall.Exec` (replaces) |
| Workspace mount | No | Yes (`-w`) |
| Device auto-detect | No | Yes |
| Use case | Quick commands + notification | Full container setup + command |

Use `charly cmd` for quick operations on running services. Use `charly shell -c` when you need workspace mounts, device passthrough, or need to start a new container.

## Cross-References

### Prerequisite

- `/charly-build:pull` -- **Required** before `charly shell` can work on a fresh host. Fetches the image into local storage so `ExtractMetadata` can read its OCI labels. Handles remote refs (`@github.com/...`) that `charly shell` itself rejects.

### Deploy-mode neighbors

- `/charly-core:cmd` -- Single command execution with D-Bus notification (running containers only)
- `/charly-automation:tmux` -- Persistent tmux sessions (survives disconnects, needed for TTY-dependent TUI programs)
- `/charly-core:service` -- Starting background services before exec
- `/charly-core:start` -- Same `appendAutoDetectedEnv()` injection at service-start time
- `/charly-core:charly-config` -- Deployment setup + same `appendAutoDetectedEnv()` at deploy time; `--no-autodetect` flag disables it
- `/charly-core:deploy` -- `charly.yml` overlay applied to labels before shell spawns
- `/charly-check:cdp` -- Chrome DevTools Protocol automation
- `/charly-check:wl` (sway subgroup) -- Sway compositor control
- `/charly-core:charly-doctor` -- Host hardware probe that feeds `appendAutoDetectedEnv()` (DRINODE, HSA_OVERRIDE_GFX_VERSION)
- `/charly-build:settings` -- Engine and bind address settings

### Build-mode references

- `/charly-image:image` -- Box definitions (ports, volumes, env) in `charly.yml`; authoritative source before a pull
- `/charly-build:build` -- Build the image you intend to shell into

### Layer skills

- `/charly-distros:nvidia`, `/charly-distros:rocm` -- GPU layers consuming the auto-injected env

## When to Use This Skill

**MUST be invoked** when the task involves charly shell command, interactive shells, command execution in containers, workspace mounts, TTY allocation, or port relay. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** Any time. Interactive access to running or stopped containers.
