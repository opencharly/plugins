---
name: service
description: |
  MUST be invoked before any work involving: charly start/stop/status/logs/update/remove commands, charly config (deployment), init system service management, or container lifecycle.
---

# Service - Service Management

## Terminology note

**"pod"** is the user-visible term for a single-container deployment (matches podman's vocabulary and the `target: pod` deploy-yml value). Internally, the Go struct is `PodDeployTarget` and the file is `charly/deploy_target_pod.go`. This skill's body uses the word "container" in many places because it's also the generic runtime artifact — read "container" as the runtime concept and "pod" as the target/deployment kind.

`charly start/stop/status/logs/shell` operate on named pod deployments (the unit a user cares about); the underlying runtime is podman/docker (containers), managed via systemd user quadlet.

## Overview

Container service lifecycle management with two modes: **quadlet** (systemd user services via podman quadlet, always preferred) and **direct** (`<engine> run -d` / `<engine> stop`, fallback only for platforms without quadlet support). Also manages individual init system services inside running containers (supervisord, systemd, etc. -- configured via the embedded `init:` vocabulary).

## Quick Reference

### Container Lifecycle

| Action | Command | Description |
|--------|---------|-------------|
| Start service | `charly start <image>` | Start as background service |
| Stop service | `charly stop <image>` | Stop running service |
| Configure deployment | `charly config <image>` | Generate .container file, daemon-reload |
| Remove deployment | `charly config remove <image>` | Remove deployment configuration |
| Service status | `charly status [<image>]` | Structured status table (IMAGE, STATUS, PORTS, TUNNEL, DEVICES, TOOLS); IMAGE merges `image[/instance]` |
| All services | `charly status --all` | Include stopped/enabled services in listing |
| Detailed status | `charly status <image>` | Detailed key-value view with live tool probes |
| JSON output | `charly status --json` | Machine-readable JSON output |
| Service logs | `charly logs <image> -f` | Follow service logs |
| Update service | `charly update <image>` | Update image and restart |
| Remove service | `charly remove <image>` | Stop, remove service + charly.yml entry |
| Purge (+ volumes) | `charly remove <image> --purge` | Also delete named volumes |
| Remove keep config | `charly remove <image> --keep-deploy` | Remove service but keep charly.yml entry |

### Supervisord Services

| Action | Command | Description |
|--------|---------|-------------|
| Service status | `charly service status <image>` | Show all service status |
| Start service | `charly service start <image> <svc>` | Start a specific service |
| Stop service | `charly service stop <image> <svc>` | Stop a specific service |
| Restart service | `charly service restart <image> <svc>` | Restart a specific service |

All commands accept `-i INSTANCE` for multi-instance support.

## Run Modes

| Mode | Config | How it works |
|------|--------|-------------|
| `quadlet` | `run_mode: quadlet` | systemd user services via podman quadlet (always preferred) |
| `direct` | `run_mode: direct` | `<engine> run -d` / `<engine> stop` (fallback only) |

```bash
charly settings set run_mode quadlet  # Recommended -- systemd integration
charly settings set run_mode direct   # Fallback for platforms without quadlet
```

## Quadlet Mode

User-level systemd services via podman quadlet. No root required.

### Setup

```bash
charly settings set run_mode quadlet
charly settings set engine.run podman    # Required
loginctl enable-linger $USER         # Required for user services
```

### Workflow

```bash
charly config my-app --bind workspace=~/project              # Generate .container file
charly config my-app -i prod --bind workspace=~/prod -e ENV=production   # Named instance
charly start my-app                    # systemctl --user start (config required first)
charly status my-app                   # systemctl --user status
charly logs my-app -f                  # journalctl --user -u (follow)
charly update my-app                   # Re-transfer image, restart
charly stop my-app                     # systemctl --user stop
charly config remove my-app            # Remove deployment configuration
charly remove my-app                   # Stop + remove .container + charly.yml entry
charly remove my-app --purge           # Also remove named volumes
charly remove my-app --keep-deploy     # Remove service but keep charly.yml for re-config
charly remove my-app -e KEY=VALUE      # Set env vars for lifecycle hooks
```

`charly config` must be run before `charly start` in quadlet mode. If the quadlet file doesn't exist, `charly start` fails with: "not configured; run 'charly config <image>' first".

### Generated Files

- Path: `~/.config/containers/systemd/charly-<image>.container` (or `charly-<image>-<instance>.container`)
- Service name: `charly-<image>.service`
- Container name: `charly-<image>`
- Ports bound to configured `bind_address`
- Entrypoint: determined by the embedded `init:` vocabulary (e.g., `supervisord -n -c /etc/supervisord.conf` for supervisord, `sleep infinity` if no init system)
- Auto-restart on failure via `WantedBy=default.target` (encrypted services with Secret Service backend include `ExecStartPre=charly config mount` + `TimeoutStartSec=0` for keyring wait; KeePass/no backend omit `WantedBy` — require `charly start`)
- `charly box validate` enforces: images with init system layers MUST include the required dependency layer (defined by the embedded `init:` vocabulary `depends_candy`)
- `Secret=charly-<image>-<name>,target=/run/secrets/<name>` for each layer-declared secret (Podman only)

### Container Secrets

When image labels declare secrets (from `charly.yml` `secrets` field), `charly config` provisions them:
1. Checks if Podman secret already exists — **if so, keeps it** (never overwrites)
2. If missing: resolves secret values from the credential store (env var > keyring > config file)
3. Creates Podman secrets via `podman secret create charly-<image>-<name>`
4. Generates `Secret=` directives in the quadlet file
5. Secrets are mounted at `/run/secrets/<name>` inside the container

**Provisioning is idempotent** — existing secrets are never overwritten. This prevents breaking stateful services (e.g., PostgreSQL) that store their own copy of the password. To force re-provisioning: `charly config <image> --refresh-secret <name>` (repeatable; `--refresh-secret all` rotates every secret of the image, sidecars included). A candy-owned auto-generated secret gets a NEW value — re-initialize services that stored the old one.

For Docker, secrets fall back to `Environment=` injection with a security warning.

### Environment Variables in Quadlet

- **`Environment=`** lines for CLI `-e` flags (inline in .container file)
- **`EnvironmentFile=`** directive for file-sourced vars (`--env-file`, workspace `.env`, or `env_file` in charly.yml)

When `EnvironmentFile=` is used, only explicit CLI `-e` vars appear as inline `Environment=` to avoid duplication.

### Security in Quadlet

Layer and image-level security settings become `PodmanArgs=` in the quadlet file:

- `privileged: true` -> `PodmanArgs=--privileged`
- `cap_add` -> `PodmanArgs=--cap-add=<CAP>`
- `devices` -> `PodmanArgs=--device=<DEV>`
- `security_opt` -> `PodmanArgs=--security-opt=<OPT>`

Source: `charly/security.go`, `charly/quadlet.go`.

### Image Transfer

When `engine.build=docker`, `charly config` auto-detects if the image is missing from podman and transfers via `docker save | podman load`. `charly update` re-transfers if needed.

## Direct Mode (Fallback)

Only use direct mode on platforms that don't support quadlet (e.g., macOS Docker Desktop).

```bash
charly start my-app                  # docker/podman run -d
charly start my-app --bind workspace=~/project  # With volume binding
charly start my-app -e LOG=debug     # With env vars
charly status my-app                 # docker/podman inspect
charly logs my-app -f                # docker/podman logs -f
charly stop my-app                   # docker/podman stop
charly update my-app --build         # Rebuild, stop old, start new
charly remove my-app                 # Stop + remove container
charly remove my-app --purge         # Also remove named volumes
```

## Init System Service Management

Manage individual services inside a running container (uses the init system configured via the embedded `init:` vocabulary — supervisord, systemd, etc.):

```bash
charly service status my-app               # Show status of all services
charly service start my-app traefik        # Start a specific service
charly service stop my-app traefik         # Stop a specific service
charly service restart my-app traefik      # Restart a specific service
charly service status my-app -i prod       # Named instance
```

The service name must match an entry in the image's init system config. Available services are validated against the image's `ai.opencharly.service.<init>` label (e.g., `ai.opencharly.service.supervisord`). The management tool and commands are resolved from the embedded `init:` vocabulary at build time and **baked into the `ai.opencharly.init_def` label**; `charly service …` reads that label (so any vocabulary-declared init system — including custom ones — works at runtime, not just at build), falling back to the built-in `supervisord`/`systemd` registry only for images built before the label existed.

Source: `charly/service.go`.

## Lifecycle Hooks

Layers can declare hooks that run on the host at specific points:

```yaml
# In charly.yml:
hook:
  post_enable: |
    echo "Service enabled for $CHARLY_IMAGE"
  pre_remove: |
    echo "Cleaning up before removal"
```

| Hook | When it runs |
|------|-------------|
| `post_enable` | After `charly config` generates the quadlet and reloads systemd |
| `pre_remove` | Before `charly remove` stops and removes the service |

Hooks from multiple layers are concatenated in layer order. Scripts run on the host (not inside the container). Use `charly remove -e KEY=VALUE` to pass environment variables to hook scripts.

Source: `charly/hooks.go`.

## Multi-Instance Support

The `-i NAME` flag enables running multiple containers of the same image with separate state:

```bash
charly config my-app -i prod --bind workspace=~/prod
charly config my-app -i staging --bind workspace=~/staging
charly start my-app -i prod
charly status my-app -i staging
```

Instance naming affects:
- Container name: `charly-<image>` -> `charly-<image>-<instance>`
- Volume names: `charly-<image>-<name>` -> `charly-<image>-<instance>-<name>`
- Quadlet file: `charly-<image>.container` -> `charly-<image>-<instance>.container`
- Service name: `charly-<image>.service` -> `charly-<image>-<instance>.service`

Source: `charly/volumes.go` (`InstanceVolumes`), `charly/quadlet.go`.

## Data Provisioning

Data from data candies is automatically provisioned into bind-backed volumes during `charly config` and synced during `charly update`. See `/charly-core:charly-config` for `--seed`/`--force-seed`/`--data-from` flags. Source: `charly/data.go`.

## Troubleshooting

### Port Already in Use

If `charly start` fails with `bind: address already in use`, another container or host process is using the port. Find the conflict:

```bash
ss -tlnp | grep <port>           # Find what's listening (host-level, not a charly resource)
charly status --json | jq -r '.[] | select(.ports[]?.host_port == <port>) | .image'   # Find the charly container
```

Stop the conflicting container before starting. Common conflicts: standalone `ollama` container on 11434, existing VNC on 5900.

### Service Crash-Looping

If `charly service status` shows a service cycling STARTING/STOPPED, run it manually to see the error:

```bash
charly service stop <image> <service>
charly shell <image> -c "<service-command>"
```

## Status Output

`charly status` shows a structured table of all charly containers. The table
has a TUNNEL column and the IMAGE column merges `image[/instance]`:

```
IMAGE                              STATUS   PORTS                 TUNNEL                  DEVICES  TOOLS
sway-browser-vnc                   running  5900,9222,9224        -                       dri,gpu  cdp:9222,dbus,charly,supervisord,sway,vnc:5900,wl
selkies-desktop/work               running  3001,9240             tailscale (all ports)   -        cdp:9240,dbus,charly,supervisord,wl
selkies-desktop/personal           running  3002,9241             tailscale (all ports)   -        cdp:9241,dbus,charly,supervisord,wl
ollama                             running  11434                 -                       gpu      dbus,charly,supervisord
jupyter                            stopped  8888                  tailscale (all ports)   -        -
```

- **IMAGE**: `image` for base deploys, `image/instance` for multi-
  instance — matches the `deployKey` shape used in `charly.yml` keys and
  `-i <inst>` flags.
- **PORTS**: Sorted, deduped host port numbers. **Source priority**:
  runtime `podman ps` mappings → `charly.yml` `port:` → image OCI label
  `ai.opencharly.port`. The runtime path uses the structured
  `[]PortMapping` carried on `ContainerSnapshot`; deploy/label paths go
  through canonical `ParsePortMapping` so the IPv4-prefixed
  `127.0.0.1:H:C/proto` form parses correctly.
- **TUNNEL**: `provider (all ports)` / `provider (ports H,H,H)` /
  `provider` / `-`. Read from `charly.yml` only — tunnel config is
  deploy-yml-only (see `labels.go:238`).
- **DEVICES**: Compact tokens (`gpu`, `dri`, `kvm`, `fuse`, `tun`),
  sorted alphabetically.
- **TOOLS**: Live-probed tools with actual host ports, sorted
  alphabetically. Port-based tools show `name:port`; socket-based show
  just the name; non-running containers show `-`.

### Tool Probes

`charly status` runs the probe set per running container with two distinct
shapes:

- **Host probes** (cdp, vnc) run from the operator's machine using the
  port mappings already on `ContainerSnapshot` — no `podman port` /
  `podman inspect` per probe.
- **Guest probes** (supervisord, dbus, charly, wl, sway) batch into a
  **single `podman exec sh -c '<concat>'`** invocation per container.
  Each probe contributes a `Snippet()` that prints `KEY=value` lines; the
  batcher delimits sections with `===PROBE:<name>===` markers and
  dispatches each section to its probe's `Parse`.

| Tool | Kind | Snippet / Probe | What it checks |
|------|------|-----------------|---------------|
| supervisord | guest | `command -v supervisorctl && supervisorctl status` | Process manager health, service count (`N/M running`) |
| cdp | host | HTTP GET `<host_port_for_9222>/json` | Chrome DevTools Protocol (no `podman port` shell-out) |
| vnc | host | TCP + RFB banner read on `<host_port_for_5900>` | VNC server (wayvnc) |
| sway | guest | discover SWAYSOCK then `swaymsg -t get_outputs` | Sway compositor (output dimensions in detail) |
| wl | guest | `command -v wtype/wlrctl/grim/pixelflux-screenshot` | Wayland tools (one snippet, four checks) |
| dbus | guest | `pgrep -x dbus-daemon` + scan for swaync/mako/dunst | D-Bus session bus + notifier (one snippet, four checks) |
| charly | guest | `command -v charly && charly version` | In-container charly binary + CalVer version |

The `wl:` verb has its own `status` method (a `wl: status` step); the
`vnc` and `cdp` status are the declarative `vnc: status` / `cdp: status` verbs
(served out-of-process by candy/plugin-vnc / candy/plugin-cdp).
These all use the same probe types via `runGuestProbes` / `cdpProbe.ProbeHost` /
`vncProbe.ProbeHost`.

**Note:** `supervisorctl status` exits with code 3 when any service
isn't RUNNING (e.g. FATAL, STOPPED). The probe's `Snippet` ends with
`|| true` so the outer shell never sees the non-zero exit; `Parse`
classifies output regardless of exit code.

### Single Image Detail

`charly status <image> -i <inst>` shows a detailed key-value view:

```
Image:     selkies-desktop
Instance:  work
Status:    running (Up 3 days)
Container: charly-selkies-desktop-work
Mode:      quadlet
Ports:     3001:3000/tcp, 9240:9222/tcp
Devices:   nvidia.com/gpu=all, /dev/dri/renderD128
Tools:     cdp:9240 (ok), dbus (ok), charly (ok), supervisord (ok), wl (ok)
Volumes:   charly-selkies-desktop-work-data -> /home/abc/data
Network:   charly
Tunnel:    tailscale (all ports)
```

### JSON Output

`charly status --json` emits an array; `charly status <image> --json` emits a
single object. `ports` is a structured array (not `[]string`):

```json
{
  "ports": [
    { "host_ip": "127.0.0.1", "host_port": 9240, "container_port": 9222, "protocol": "tcp" }
  ],
  "tunnel": "tailscale (all ports)"
}
```

### Reaping Orphans

Use the top-level `charly reap-orphans` command. It walks charly.yml
ephemeral entries marked `active`, probes the underlying engine
(libvirt for VM, podman for pod, kubectl for k8s) and runs `charly bundle
del <name> --force` for orphans.

Source: `charly/status_collector.go` (the collection engine — substrate fan-out + deploy enrichment; the pod/local live collectors moved to `candy/plugin-substrate` in P14a, the vm/k8s/android collectors + the pod deploy-enrichment stay here until K5), `charly/status_reap.go` (orphan reaping). The status CLI + render moved to `candy/plugin-status`; the live tool probes to `candy/plugin-substrate/status_probes.go` (P14a).

## Cross-References

- `/charly-build:pull` -- Prerequisite: fetch the image into local storage; handles remote refs (`@github.com/...`) and the `ErrImageNotLocal` recovery path

- `/charly-core:shell` -- Interactive shells and exec into running containers
- `/charly-core:deploy` -- Quadlet generation details, tunnels, volume backing
- `/charly-automation:enc` -- Encrypted storage (mounted inline by charly start)
- `/charly-core:charly-config` -- `run_mode`, `auto_enable`, `engine.run` settings
- `/charly-check:cdp` -- the `cdp:` check verb (`cdp: status`, served out-of-process by candy/plugin-cdp)
- `/charly-check:vnc` -- the `vnc:` check verb (`vnc: status`, served out-of-process by candy/plugin-vnc)
- `/charly-check:wl` -- Desktop automation + the `wl:` verb's sway-* methods (e.g. a `wl: sway-tree` step)
- `/charly-check:wl` -- the `wl: status` method (tool availability check)

## When to Use This Skill

**MUST be invoked** when the task involves starting, stopping, configuring, or managing container services, init system service management, or container lifecycle. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** After `/charly-build:build` and `/charly-core:deploy`. This skill covers the runtime lifecycle.
Previous step: `/charly-core:deploy` (quadlet generation, tunnels). Next step: per-pod plugin (`/charly-jupyter:<name>`, `/charly-coder:<name>`, etc.) or `/charly-distros:<name> / /charly-languages:<name> / /charly-infrastructure:<name> / /charly-tools:<name>` for verification.
