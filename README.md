# OpenCharly Plugins

Claude Code and Codex plugins for OpenCharly — the candy factory for you and your agents.

## How this marketplace is organized

Plugins are sorted into **four use-case buckets**:

| Bucket | When to install | Plugins |
|---|---|---|
| **commands** | "I want to run charly verbs" | `charly-core`, `charly-build`, `charly-check`, `charly-automation` |
| **kind** | "I want to author the YAML schema for an entity" | `charly-image`, `charly-vm`, `charly-kubernetes`, `charly-local`, `charly-pod` |
| **development** | "I'm a contributor working on the charly source code itself" | `charly-internals` |
| **images** | "I want to deploy a specific image" | `charly-distros`, `charly-languages`, `charly-infrastructure`, `charly-tools`, `charly-jupyter`, `charly-coder`, `charly-selkies`, `charly-openclaw`, `charly-versa`, `charly-ollama`, `charly-openwebui`, `charly-comfyui`, `charly-immich`, `charly-hermes`, `charly-filebrowser` |

The directory layout under `plugins/` is **flat** — every plugin sits at
`plugins/<name>/` (no `charly-` prefix in directory names). The `charly-` prefix
lives exclusively in each `plugin.json`'s `name:` field, which means every
skill invocation is `/charly-<plugin>:<skill>` (e.g. `/charly-core:ssh`,
`/charly-jupyter:jupyter`, `/charly-distros:arch`). The `category:` field in
`marketplace.json` provides the four-bucket grouping for the plugin
manager UI.

## Plugins by bucket

### commands — runtime CLI verbs

| Plugin | Skill count | MCP server | Purpose |
|---|--:|---|---|
| **charly-core** | 15 | — | Lifecycle: start, stop, restart, charly-status, logs, shell, ssh, deploy, charly-update, remove, charly-config, cmd, charly-version, charly-doctor, clean. |
| **charly-build** | 13 | — | Build/authoring: build, generate, list, inspect, merge, new, pull, validate, secrets, settings, migrate, reconcile, charly-mcp-cmd. |
| **charly-check** | 13 | — | Live-container evaluation: `check` orchestrator + cdp, wl, wl-overlay, dbus, vnc, spice, libvirt, record, adb, appium probes + `android` (the `kind: android` device + `apk:` package format + Android-device deploy) + the `check-sway-browser-vnc-pod` R10 bed. |
| **charly-automation** | 6 | — | tmux verb, host-side wrappers (alias, udev), topic flags (enc, sidecar, openclaw-deploy). |

### kind — schema-kind authoring

| Plugin | Skill count | MCP server | Purpose |
|---|--:|---|---|
| **charly-image** | 2 | — | Schema for `kind: box` and `kind: candy` (charly.yml authoring). |
| **charly-vm** | 6 | — | Schema for `kind: vm` + bootc VM catalog (cloud_image vs bootc, libvirt/QEMU). Includes `cachyos` (bootstrap VM, in the `opencharly/distro-cachyos` submodule) and `debian` / `ubuntu` (debootstrap bootstrap VMs, in the `opencharly/distro-debian` / `opencharly/distro-ubuntu` submodules). |
| **charly-kubernetes** | 2 | — | Schema for `kind: k8s` + cluster probes via the declarative `kube:` check verb (out-of-process `candy/plugin-kube`). |
| **charly-local** | 3 | — | Schema for `kind: local` + ssh-host deploys + managed ssh-config fragment. Includes `charly-cachyos` (operator CachyOS workstation profile, in the `opencharly/distro-cachyos` submodule). |
| **charly-pod** | 1 | — | Schema for `kind: pod` and the `bundle` deploy kind — thin pointer to `/charly-core:deploy` for verb details. |

### development — contributor-only internals

| Plugin | Skill count | MCP server | Purpose |
|---|--:|---|---|
| **charly-internals** | 17 + 5 agents | github (stdio) | Go source map, install-plan IR, capabilities/OCI labels, vm-spec, libvirt/cloud-init renderers, egress (validating the config files charly WRITES), cutover-policy, strict-policy, disposable, ovmf, generate-source, git-workflow, skills, agents (the agents/workflows/teams guide). Ships 5 agents — enforcers root-cause-analyzer, layer-validator, testing-validator; executors check-bed-runner, deploy-verifier (drive the `charly check` beds). The `/verify-beds` + `/audit-deploy-configs` dynamic workflows live in the superproject's `.claude/workflows/`. |

### images — deployable image catalog

#### Foundation layers (`charly-distros` / `charly-languages` / `charly-infrastructure` / `charly-tools`)

| Plugin | Skill count | MCP server | Purpose |
|---|--:|---|---|
| **charly-distros** | 34 | — | Base OS images, GPU runtime, per-distro builders. fedora (+ fedora-builder, fedora-nonfree — the base stack is owned by the `opencharly/distro-fedora` submodule, which is self-contained (`import: []`); the charly-fedora / fedora-test showcase images are owned by that submodule too), arch (+ arch-builder, owned by the self-contained `opencharly/distro-arch` submodule), cachyos (+ cachyos-pacstrap/-builder, owned by the `opencharly/distro-cachyos` submodule, which imports the `arch` namespace), debian / ubuntu (+ their `-builder` and `-debootstrap`/`-debootstrap-builder`, owned by the `opencharly/distro-debian` / `opencharly/distro-ubuntu` submodules), nvidia, cuda, rocm, etc. The `nvidia` GPU base image now lives in the `opencharly/distro-fedora` submodule (the `nvidia` / `cuda` / `rocm` layers stay in main). |
| **charly-languages** | 4 | — | Programming language runtimes — pixi, python, python-ml, python-ml-layer. (golang/rust/nodejs live in `charly-coder` because they're tightly coupled to dev images.) |
| **charly-infrastructure** | 22 | — | Databases, networking, security, system services. postgresql, redis, valkey, vectorchord, k3s, traefik, supervisord, tailscale, gocryptfs, virtualization, dbus-layer, tmux-layer, ssh-client, gnupg, etc. |
| **charly-tools** | 19 | — | CLI utilities and the `charly` binary — ripgrep, himalaya, whisper, nano-pdf, summarize, ordercli, gogcli, sherpa-onnx, songsee, blogwatcher, sag, xurl, goplaces, mcporter, yay, vscode, charly, cue. |

#### Per-pod plugins

| Plugin | Skill count | MCP server | Purpose |
|---|--:|---|---|
| **charly-jupyter** | 15 | jupyter @ 8888 | Jupyter image family (jupyter, jupyter-ml, jupyter-ml-notebook, unsloth-studio) + notebook templates + jupyter-mcp server. |
| **charly-coder** | 31 | charly @ 18765 | charly coder/dev images (fedora-coder in the `opencharly/distro-fedora` submodule; arch-coder/charly-arch in `opencharly/distro-arch`; debian-coder in `opencharly/distro-debian`; ubuntu-coder in `opencharly/distro-ubuntu`) + language runtimes (golang/rust/nodejs/docker-ce). |
| **charly-selkies** | 43 | chrome-devtools @ 9224 | Selkies-desktop family — labwc and full-KDE-Plasma flavors of the browser-streamed Wayland desktop, always a headless pod, per-GPU encode (VAAPI / NVENC / x264 auto-selected at runtime). |
| **charly-openclaw** | 7 | — | OpenClaw AI gateway family (CachyOS base): the `openclaw` layer + headless `openclaw` / `openclaw-full` images + the all-in-one `openclaw-desktop` (streaming desktop + gateway + CPU ollama + nested charly toolchain) + composition layers (`openclaw-full`, `openclaw-full-ml`). |
| **charly-versa** | 9 | marimo @ 22718, airflow @ 29999 | Versa image — marimo notebook + Airflow + OSM/GTFS analytics + martin vector tiles. |
| **charly-ollama** | 2 | — | Ollama LLM-server image. Pair with `charly-jupyter` to expose to notebooks. |
| **charly-openwebui** | 2 | — | OpenWebUI chat frontend. Consumes the jupyter MCP. |
| **charly-comfyui** | 2 | — | ComfyUI image-generation/diffusion. |
| **charly-immich** | 4 | — | Immich photo-management (immich + immich-ml variants). |
| **charly-hermes** | 6 | — | Hermes agent image (hermes + hermes-playwright variants). Consumes the jupyter MCP. |
| **charly-filebrowser** | 2 | — | Filebrowser web file management on top of an charly volume. |

## Skill invocation pattern

Every skill uses the namespaced form `/<plugin-name>:<skill-name>`. The
plugin name carries the `charly-` prefix; the skill name does not. Examples:

- `/charly-core:ssh` — open an interactive shell into a pod.
- `/charly-image:layer` — schema authoring for `kind: candy`.
- `/charly-distros:arch` — Arch Linux base image reference.
- `/charly-jupyter:notebook-templates` — bundled notebook starter content.
- `/charly-check:cdp` — Chrome DevTools Protocol live probe.

## Skill name uniqueness

Every skill in this marketplace has a globally-unique folder name. Where a
short name could be ambiguous, the canonical names are:

- `charly-infrastructure:tmux-layer` (the tmux package layer) vs `charly-automation:tmux` (the verb).
- `charly-infrastructure:dbus-layer` (the D-Bus service layer) vs `charly-check:dbus` (the verb).
- `charly-automation:openclaw-deploy` (the deployment topic) vs `charly-openclaw:openclaw` (the image).
- `charly-vm:vms-catalog` (the VM catalog skill) vs the kind-name `vm`.
- `charly-build:generate` (the build verb) vs `charly-internals:generate-source` (the source-reading reference).
- `charly-distros:arch` (the distro) vs `charly-vm:arch-cloud-vm` (the cloud VM).
- `charly-vm:cachyos-bootstrap-vm`, `charly-vm:debian-debootstrap-vm`, and
  `charly-vm:ubuntu-debootstrap-vm` identify bootstrap VMs without colliding
  with their distro skills.

## Recent changes

See this repo's [`CHANGELOG/`](CHANGELOG/README.md) — and the superproject's
[`CHANGELOG/`](../CHANGELOG/README.md) for older project-wide history — for the
full history of plugin reorganizations, skill renames, and marketplace version
bumps (one file per CalVer version). This index and the skill docs themselves describe
only the current structure.

## Installation

Use the same marketplace and skill tree in either harness:

```bash
./setup claude                         # full developer mode (default)
./setup codex developer
./setup claude user                    # use/author Charly, do not develop it
./setup codex container jupyter        # operate one generated container family
./setup codex --check developer        # non-mutating drift check
```

`developer` installs all 25 plugins. `user` installs the runtime, authoring,
checking, kind, and foundation plugins but not contributor internals or a
container family. `container FAMILY` installs `charly-core` plus one
self-contained family plugin. The Charly repository always uses `developer`.

The setup command writes only target-repository files: Claude writes
`.claude/settings.json`; Codex writes `.agents/plugins/marketplace.json` and
repo-native `.agents/skills/` symlinks to the selected canonical
`plugins/<plugin>/skills/` directories. It never copies skill bodies, invokes a
plugin CLI, or changes user configuration. Existing unrelated project settings,
marketplace metadata, plugin entries, and skill paths are preserved; setup owns
only the Charly entries it generates. It is idempotent and does not change
models, approval policy, credentials, trust, or permissions. A consumer
repository must carry the Charly plugins repository at `./plugins`.
Existing MCP declarations bundled by plugins remain normal plugin content;
MCP is not required to install, select, or synchronize the skills.
