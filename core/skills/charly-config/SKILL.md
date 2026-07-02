---
name: charly-config
description: |
  MUST be invoked before any work involving: charly config commands, image deployment setup, quadlet generation, secrets provisioning, encrypted volumes, data seeding, or volume backing configuration.
  Named `charly-config` (not `config`) to disambiguate from Claude Code's built-in `/config` slash command.
---

# charly config -- Image Deployment Configuration

## Overview

`charly config` configures an image for deployment. In `run_mode=quadlet` (the default on systemd-user hosts) it generates a systemd quadlet unit, provisions container secrets, initializes encrypted volumes, and seeds data from data candies into the image's volumes. In `run_mode=direct` (auto-selected on nested environments without systemd-user — check-sandbox pods, supervisord-only containers, sysvinit hosts) it skips quadlet+systemctl and runs the container via `podman run -d`, recording a marker file at `~/.config/charly/direct/<name>.json` so `charly start`/`charly remove` can find it. Direct mode does NOT support sidecars, encrypted volumes, or cloudflare tunnel companion services (those require systemd) — warnings are emitted and the operation proceeds without those features.

This is the **single entry point** for **container** deployment setup. `charly start` requires `charly config` to have been run first in quadlet mode.

**Relationship to `charly bundle add`** — `charly config` remains the primary way to create/update a quadlet and provision secrets/volumes/sidecars for a container deploy. `charly bundle add <name> <ref>` (container target) wraps both `charly config` and `charly start` and additionally handles `--add-candy` overlay synthesis (an overlay Containerfile is built before the quadlet references the resulting overlay image). `charly bundle add host` bypasses `charly config` entirely — the host target has no quadlet; it writes systemd units directly (when `--with-services` is enabled) and records every action in the ledger at `~/.config/opencharly/installed/`. See `/charly-core:deploy` for the command family and `/charly-local:local-deploy` for host-target semantics.

**`charly config` vs `charly settings` — common verb confusion.** `charly config <image>` configures an image for deployment (quadlet + secrets + volumes + data seed). `charly settings list` shows runtime config keys (secret_backend, vm.backend, etc.). A trailing `charly config show` parses as `charly config setup show` with `show` as the image positional — and errors with `image "show" is not available locally`. To inspect runtime configuration use `charly settings list`; to inspect a configured image's resolved deploy state use `charly box inspect <image>` or `charly bundle show <name>`.

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| Full setup | `charly config <image>` | Quadlet + secrets + volumes + data seed |
| Instance setup | `charly config <image> -i <instance>` | Deploy named instance with separate config |
| With bind mount | `charly config <image> --bind workspace=~/project` | Bind workspace to host dir |
| With encryption | `charly config <image> --encrypt data` | Encrypted volume via gocryptfs |
| Volume config | `charly config <image> -v data:bind:/mnt/nas` | Explicit volume backing |
| Manual passwords | `charly config <image> --password manual` | Prompt for each secret |
| Re-seed data | `charly config <image> --force-seed` | Overwrite existing data |
| Seed from other image | `charly config <image> --data-from data-image:v1` | Use separate data image |
| No data seed | `charly config <image> --no-seed` | Skip data provisioning |
| Keep mounts | `charly config <image> --keep-mounted` | Keep encrypted volumes mounted after setup |
| Show status | `charly config status <image>` | Show encrypted volume status |
| Mount volumes | `charly config mount <image>` | Mount encrypted volumes |
| Unmount volumes | `charly config unmount <image>` | Unmount encrypted volumes |
| Change password | `charly config passwd <image>` | Change gocryptfs password |
| Remove config | `charly config remove <image>` | Remove quadlet and disable service |

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `setup` (default) | Full setup: quadlet + secrets + encrypted volumes + data seed |
| `status` | Show encrypted volume mount status |
| `mount` | Mount encrypted volumes |
| `unmount` | Unmount encrypted volumes |
| `passwd` | Change gocryptfs password |
| `remove` | Remove quadlet file and disable systemd service |

## Setup Flags

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--tag` | | `latest` | Image tag to use |
| `--build` | | | Force local build instead of pulling |
| `--env` | `-e` | | Set container env var (KEY=VALUE), merged with existing vars (upsert by key) |
| `--clean` | `-c` | | Replace all env vars instead of merging (clean slate) |
| `--env-file` | | | Load env vars from file |
| `--instance` | `-i` | | Instance name (multiple containers of same image) |
| `--port` | `-p` | | Remap host port (newHost:containerPort) |
| `--keep-mounted` | | | Keep encrypted volumes mounted after setup |
| `--password` | | `auto` | `auto`: generate secrets, `manual`: prompt for each |
| `--volume` | `-v` | | Configure volume backing (name:type[:path]). Type: volume\|bind\|encrypted |
| `--bind` | | | Shorthand: configure volume as bind mount (name or name=path) |
| `--encrypt` | | | Shorthand: configure volume as encrypted (gocryptfs) |
| `--seed` | | `true` | Seed image volumes (bind mounts AND named volumes) with data from the image's data candies |
| `--no-seed` | | | Disable data seeding |
| `--force-seed` | | | Re-seed even if target directory is not empty |
| `--data-from` | | | Seed data from a different data image |
| `--no-autodetect` | | | Disable GPU/device auto-detection (skips DRINODE, DRI_NODE, HSA_OVERRIDE_GFX_VERSION injection) |
| `--ssh-key` | | `auto` | SSH public key: `auto` (default ~/.ssh key), path to .pub file, `generate`, or `none` |
| `--update-all` | | | Regenerate quadlets for all other deployed images to pick up service env changes |
| `--memory-max` | | | Cgroup `memory.max` hard OOM limit (e.g. `6g`, `500m`). Persists to charly.yml. |
| `--memory-high` | | | Cgroup `memory.high` soft limit — reclaim pressure kicks in before OOM. Persists to charly.yml. |
| `--memory-swap-max` | | | Cgroup `memory.swap.max` ceiling (e.g. `2g`). Persists to charly.yml. |
| `--cpus` | | | CPU quota in cores (e.g. `2.5` for 2.5 cores). Persists to charly.yml. |

## How It Works

1. Requires `run_mode=quadlet` (errors if set to `direct`)
2. Resolves image reference (local or remote `github.com/...`)
3. Ensures image exists in run engine (transfers if needed)
4. Extracts metadata from OCI image labels
5. Generates quadlet `.container` file in `~/.config/containers/systemd/`
6. Provisions container secrets (from `ai.opencharly.secret` label)
7. Resolves volume backing (named, bind, or encrypted)
8. Initializes encrypted volumes (gocryptfs) if configured
9. Seeds data candies into the image's volumes (bind mounts AND podman named volumes)
10. Runs `systemctl --user daemon-reload`
11. Injects `env_provide` entries from image labels into charly.yml `provides.env:` (resolves `{{.ContainerName}}` templates)
12. Injects `mcp_provide` entries from image labels into charly.yml `provides.mcp:` (resolves templates, defaults transport to `http`)
13. Synthesizes `CHARLY_MCP_SERVERS` JSON env var for consumer containers (pod-aware: same-image entries resolve to `localhost`)
14. Warns about missing `mcp_require` servers (same pattern as `env_require` warnings)
15. If `--update-all`, regenerates quadlets for all other deployed images (preserving Instance, Tunnel, PodName, Sidecars, and instance-scoped volume names) and reloads systemd

## Volume Backing

Volumes declared in charly.yml default to named volumes. At `charly config` time, backing can be changed per-volume:

```bash
# Named volume (default)
charly config my-app

# Bind mount to host directory
charly config my-app --bind workspace=~/project
charly config my-app -v workspace:bind:~/project    # Equivalent

# Encrypted (gocryptfs)
charly config my-app --encrypt data
charly config my-app -v data:encrypted              # Equivalent
charly config my-app -v data:encrypt:/mnt/ssd       # With explicit path

# Multiple volumes
charly config my-app --bind workspace=~/project --encrypt data -v models:bind
```

Auto-path for bind without explicit host path: `<volumes_path>/<image>/<name>` (default: `~/.local/share/charly/volumes/`).

### Bind-mounting a project checkout for `charly mcp serve`

The `charly-mcp` layer declares a `project` volume at `/workspace` (the volume NAME stays `project` for a stable deployer API) and sets `env: CHARLY_PROJECT_DIR=/workspace`. Bind-mount your opencharly checkout at config time so build-mode MCP tools (`box.build`, `box.list.boxes`, `box.inspect`) can read `charly.yml`. Alternatively, skip the bind-mount and `charly mcp serve` will auto-fall back to the upstream `opencharly/charly` repo (see `/charly-build:charly-mcp-cmd` "Project-dir wiring"):

```bash
charly config charly-arch --bind project=/home/you/opencharly
charly start charly-arch
charly check live charly-arch --filter mcp
# → the baked mcp: call box.list.boxes step lists images from the bind-mounted /home/you/opencharly
```

The `CHARLY_PROJECT_DIR` env var is consumed by the charly binary's global `-C` / `--dir` / `CHARLY_PROJECT_DIR` flag (`charly/main.go` calls `os.Chdir(Dir)` before Kong dispatch). See `/charly-image:image` "Project directory resolution" and `/charly-build:charly-mcp-cmd` "Deployment: the `charly-mcp` layer" for the full pattern.

## Secret Provisioning

Secrets declared in `charly.yml` `secret:` field are stored as OCI label metadata. At config time:

- `--password auto` (default): generates random passwords for all secrets
- `--password manual`: prompts for each secret

**Idempotent:** existing Podman secrets are never overwritten. To force re-provisioning: `charly config <image> --refresh-secret <name>` (repeatable; `all` rotates every secret of the image, sidecars included; a candy-owned auto-generated secret gets a NEW value — re-initialize services that stored the old one). Unknown names produce a warning naming the image.

## Data Seeding

Data candies (candies with `data:` field) stage files into `/data/<volume>/<dest>/` at build time. At config time:

- **First config** (`--seed`, default true): copies staged data into the image's volumes (both bind mounts and named volumes)
- **Subsequent config**: skips if `data_seeded` flag is set in charly.yml
- **`--force-seed`**: re-seeds even if directory is not empty
- **`--data-from <image>`**: seeds from a separate data image instead of the target image

### Volume-kind dispatch

Seeding runs for both volume backings, with a minor difference in how podman is invoked:

- **Bind mount** (`--bind <name>` or `--bind <name>=<path>`, or `type: bind` in charly.yml): the seeder runs `podman run --rm -v <host-path>:/seed --userns=keep-id:uid=<UID>,gid=<GID> <image> bash -c "cp -a /data/<vol>/. /seed/"`. The `--userns=keep-id` aligns the in-container UID with the real host UID so files end up owned by the host user.
- **Named volume** (the default): the seeder runs `podman run --rm -v <charly-image-name>:/seed <image> bash -c "cp -a /data/<vol>/. /seed/"` — **without** `--userns=keep-id`. Named volumes live in the rootless subuid space; the runtime container reads them without keep-id, so the seeder must write with the same identity.

For `FROM scratch` data images (`data_image: true`), bind-mount targets use `podman create` + `podman cp` (the simpler path), and named-volume targets use `podman run --mount type=image,src=<scratch>,dst=/staging,rw=false` with a lightweight `busybox:stable` helper image as the runnable side (pulled lazily on first use).

### Emptiness check

`DataProvisionInitial` only runs when the target is empty:

- **Bind mount**: checks the per-entry subdirectory (`<bind-root>/<dest>/`) via `os.ReadDir`, so data candies with distinct `dest:` values can coexist in the same bind mount.
- **Named volume**: checks the volume root via `podman volume inspect --format {{.Mountpoint}}` followed by `os.ReadDir` of the returned path. Per-entry subdirectory checks aren't available without exec'ing into a container, so multiple entries targeting the same named volume all run on the initial seed and then transition to merge-safe `cp -an` on subsequent runs.

### Data candy ordering (bind mounts only)

For **bind-mounted** targets, data candies that target the volume **root** (`dest:` absent or empty — e.g. `notebook-templates`, which drops `getting-started.ipynb` directly into `~/workspace/`) should be listed **first** in the box's `candy:` list. A root-targeted candy ordered after subdirectory-targeted candies will see the root as non-empty (because subdirs from earlier candies exist) and skip. This is a convention, not a hard-enforced rule.

This ordering caveat does not apply to named-volume targets, where the initial seed runs against the whole volume regardless of sub-paths.

## Encrypted Volumes

Encrypted volumes use gocryptfs. Each volume gets `{cipher,plain}` subdirectories:

- Default path: `<encrypted_storage_path>/charly-<image>-<name>/`
- Explicit path: `--volume name:encrypt:/path` stores directly at `/path/{cipher,plain}`
- Mounted via `ExecStartPre=charly config mount` in the quadlet
- Each mount runs in a `systemd-run --scope` unit (survives container restart)
- `-allow_other` flag for rootless podman with `--userns=keep-id`

### Fast path: `charly config mount` short-circuit

When every requested encrypted volume for an image is already mounted — the
typical state on service restart, because `charly-enc-<image>-<volume>.scope`
units survive container stop/restart independently of the service's cgroup —
`charly config mount <image>` short-circuits and returns without touching the
credential store at all. Output is:

    All encrypted volumes for <image> already mounted (N/N)

This makes service restarts (`charly restart <image>`)
resilient to temporary keyring backend problems: the only reason to query the
keyring is to get the passphrase for a fresh `gocryptfs -init` or mount, and
the short-circuit skips that entirely when no new mount is needed. A broken
`default` alias in the Secret Service — for example, KeePassXC's FdoSecrets
plugin advertising a stub collection — does NOT block restarts.

When a volume IS unmounted and needs to be remounted, the normal path runs:
`resolveEncPassphraseForMount` queries the credential store via the
iteration-capable `ssClient` (not just the Secret Service default alias), so
even then the broken-stub scenario still resolves automatically by finding
the credential in a sibling healthy collection. See `/charly-automation:enc` for the full
iteration order, the bounded `encMountDeadline` retry behavior, and the
source classification (`env`/`keyring`/`config`/`locked`/`unavailable`/`default`).

## Resource Caps

Memory and CPU caps flow through the same `security:` block as `shm_size`.
Layers can declare defaults; image/deploy overrides replace them. CLI flags
on `charly config` persist to `charly.yml` and take effect on the next quadlet
regeneration.

```bash
# Box-level default (all instances)
charly config selkies-desktop --memory-max=6g --memory-high=5g --memory-swap-max=2g

# Per-instance override (tighter cap for one instance)
charly config selkies-desktop -i 192.241.92.221 --memory-max=8g

# CPU quota on an unrelated image
charly config jupyter --memory-max=16g --cpus=8
```

Merge rules (see `charly/security.go`):

- **Layers → image**: smallest value wins (`minCap` / `minCpus`). A tighter
  cap is a smaller blast radius, so it's the safer default.
- **Box-level and deploy-level overrides**: full replace, identical to
  how `shm_size` is handled.

Emitted as native systemd cgroup directives (`MemoryMax=`, `MemoryHigh=`,
`MemorySwapMax=`, `CPUQuota=`) in the quadlet's `[Service]` section,
guaranteed to work on every systemd version charly targets. For the runtime
(non-quadlet) path, `SecurityArgs` also emits the equivalent
`podman run --memory / --memory-reservation / --memory-swap / --cpus` flags.

`CPUQuota` uses systemd's percentage form — `--cpus=2.5` → `CPUQuota=250%`
(one full core is `100%`).

### Gotchas

- Lowercase suffixes (`6g`) are auto-normalized to `6G`. systemd silently
  parses lowercase as `infinity` — no error, just no limit — so charly coerces
  everything to the canonical uppercase form before emitting the quadlet.
- Field-level merge in deploy means `--memory-max` won't wipe co-set fields
  like `shm_size`. Unset CLI fields fall through to layer/image defaults
  rather than being replaced with zero values.
- Resource caps merge **smallest-wins** across layers (tightest cap = smallest
  blast radius). Box-level and deploy-level overrides replace entirely.

## Port-conflict detection

When a `-p HOST:CONTAINER` flag publishes onto a host port that another listener already holds, `charly config` emits a **soft warning** (does not abort) and suggests a remap:

```
Warning: port conflicts detected:
  Port 13000 is in use
    Fix: find and stop the process using port 13000
    Or remap: charly start openclaw-desktop --port 13001:3000
Wrote /home/user/.config/containers/systemd/charly-<image>-<instance>.container
```

The quadlet is still written with the conflicting port, so `charly start` will fail at bind time unless you either free the port, re-run `charly config` with a remap, or edit `charly.yml`. Detection uses a local `net.Listen` probe per published port at configure time. Handy for multi-instance deployments alongside a production fleet (e.g., running `/charly-openclaw:openclaw-desktop` as a test instance while `/charly-selkies:selkies-labwc` holds the canonical 3000/9222/9224/2222 range).

## Deploy State

All configuration is persisted to `~/.config/charly/charly.yml` in node-form — a
`version:` stamp, an optional top-level `provides:` directive, and each deploy as a
name-first `<name>: {<substrate-kind>: <scalars>, <child-nodes>}` entry (no `deploy:` map
wrapper, no `target:` field — the substrate kind at the edge selects the target):

```yaml
my-app:
  pod:
    image: my-app
    tag: latest
    data_seeded: true
    data_source: "my-app:latest"
  my-app-volume:
    volume:
      - name: workspace
        type: bind
        host: ~/project
```

## Common Workflows

### Deploy a Jupyter notebook server

```bash
charly config jupyter-ml-notebook --bind workspace=~/notebooks
charly start jupyter-ml-notebook
# Open http://localhost:8888
```

### Deploy with encrypted model cache

```bash
charly config ollama --encrypt models
# Prompted for gocryptfs password on first setup
charly start ollama
```

### Remove and reconfigure

```bash
charly config remove my-app
charly config my-app --bind workspace=/new/path
```

### Full instance removal (important: 3-step cleanup)

`charly config remove` disables the systemd service but does NOT clean the charly.yml entry. Running `--update-all` before cleaning charly.yml will re-create quadlets from stale entries. Full cleanup requires:

```bash
charly config remove <image> -i <instance>     # 1. Stop & disable service
charly bundle reset <image> -i <instance>       # 2. Remove charly.yml entry
charly remove <image> -i <instance>         # 3. Remove container + quadlet (reloads systemd)
charly reap-orphans                         # 4. Clear ghost units (optional)
```

Only THEN run `charly config <image> --update-all` to propagate the clean state.

### Multi-instance proxy deployment

Deploy multiple browser instances with different HTTP proxies (e.g., for selkies-desktop):

```bash
charly config selkies-desktop -i 198.145.102.110 \
  -e HTTP_PROXY=http://198.145.102.110:5466 \
  -e HTTPS_PROXY=http://198.145.102.110:5466 \
  -e "NO_PROXY=localhost,127.0.0.1" \
  -p 3006:3000 -p 9236:9222
charly start selkies-desktop -i 198.145.102.110
```

Each instance gets unique host ports. The Chrome layer's `chrome-wrapper` translates `HTTP_PROXY`/`HTTPS_PROXY` into Chrome's `--proxy-server` flag. Verify with the `cdp:` check verb (served out-of-process by candy/plugin-cdp) — author `cdp: status` / `cdp: open` (`url: https://ip.me`) / `cdp: eval` (`expression: document.querySelector('#ip-lookup').value`) steps and run them against the instance:

```bash
charly check live selkies-desktop -i 198.145.102.110 --filter cdp
```

## Service Environment Injection

When a configured image declares `env_provide` or `mcp_provide` in its layers (stored in OCI labels), `charly config` automatically injects those entries into the `provides:` section of `charly.yml`. This enables cross-container service discovery without manual configuration. Verify that an injected MCP endpoint is actually reachable with the `mcp:` check verb (`charly check live <image> --filter mcp`) — see `/charly-build:charly-mcp-cmd` for the full verb surface.

```yaml
# charly.yml after `charly config ollama && charly config jupyter`
provides:
  env:
    - name: OLLAMA_HOST
      value: http://charly-ollama:11434
      source: ollama
  mcp:
    - name: jupyter
      url: http://charly-jupyter:8888/mcp
      transport: http
      source: jupyter
ollama:
  pod:
    image: ollama
jupyter:
  pod:
    image: jupyter
```

**Self-exclusion (env):** An image's own env_provide vars are filtered out of its own environment — the image uses its own `env:` (e.g., `OLLAMA_HOST=0.0.0.0`), not the service discovery URL.

**Pod-aware (MCP):** When provider and consumer share a container, MCP URLs resolve to `localhost` instead of container hostname. No self-exclusion for MCP — same-container consumers always see their own MCP servers.

**Propagation:** Use `--update-all` to regenerate quadlets for all other deployed images so they pick up the new env vars immediately. Without `--update-all`, other images pick up the env vars on their next `charly config` or `charly update`.

**Cleanup:** `charly config remove` and `charly remove` automatically remove the service's injected vars from the global env.

See `/charly-image:layer` for `env_provide` field documentation.

### Instance-Aware MCP Server Naming

When deploying with `-i <instance>`, `injectMCPProvides` appends `-<instance>` to each MCP server name. This prevents naming collisions when multiple instances of the same image provide the same MCP server:

```bash
# Base deployment — MCP name: "chrome-devtools"
charly config selkies-desktop --update-all

# Instance deployment — MCP name: "chrome-devtools-31.58.9.4"
charly config selkies-desktop -i 31.58.9.4 \
  -e HTTP_PROXY=http://31.58.9.4:6077 \
  -p 3001:3000 --update-all
```

Result in `charly.yml` `provides.mcp`:
```yaml
- name: chrome-devtools
  url: http://charly-selkies-desktop:9224/mcp
  source: selkies-desktop
- name: chrome-devtools-31.58.9.4
  url: http://charly-selkies-desktop-31.58.9.4:9224/mcp
  source: selkies-desktop/31.58.9.4
```

Consumers (e.g., hermes) see both as distinct MCP servers in `CHARLY_MCP_SERVERS`. On re-config, stale MCP entries from the same source are automatically cleaned before new entries are injected.

Source: `charly/config_image.go` (`injectMCPProvides`).

## Hermes LLM Provider Auto-Configuration Example

The hermes layer uses `-e` env vars to auto-configure its LLM provider on first start. Pass the API key at config time:

```bash
# Ollama Cloud
charly config hermes -e OLLAMA_API_KEY=your-key

# OpenRouter
charly config hermes -e OPENROUTER_API_KEY=sk-or-xxx

# Local Ollama (OLLAMA_HOST auto-injected by charly config ollama --update-all)
charly config ollama --update-all
charly config hermes
```

All providers whose keys are present get registered simultaneously. Priority (`OLLAMA_HOST` > `OLLAMA_API_KEY` > `OPENROUTER_API_KEY`) only determines the default. Override model with `-e HERMES_MODEL=...`. See `/charly-hermes:hermes` for auto-provider-config details.

## Open WebUI Auto-Configuration Example

Open WebUI uses `env_require` for mandatory admin credentials and `env_accept` for optional LLM providers:

```bash
# Minimal: admin credentials required (hard error if missing)
eval "$(charly secrets gpg env)"
charly config openwebui \
  -e "WEBUI_ADMIN_EMAIL=$WEBUI_ADMIN_EMAIL" \
  -e "WEBUI_ADMIN_PASSWORD=$WEBUI_ADMIN_PASSWORD" \
  -e "OPENROUTER_API_KEY=$OPENROUTER_API_KEY" \
  -e "OLLAMA_API_KEY=$OLLAMA_API_KEY" \
  --update-all

# Full workstation: Ollama + Jupyter + OpenWebUI
charly config ollama
charly config jupyter --update-all
charly config openwebui ... --update-all
```

The entrypoint auto-configures: OpenRouter + Ollama Cloud as semicolon-separated `OPENAI_API_BASE_URLS`, MCP servers from `CHARLY_MCP_SERVERS` → `TOOL_SERVER_CONNECTIONS`, Jupyter code execution from co-deployed jupyter container. `ENABLE_OLLAMA_API` is disabled unless a local Ollama is deployed via `env_provide`. See `/charly-openwebui:openwebui` for details.

## env_require Enforcement

Layers can declare `env_require` in `charly.yml` for mandatory environment variables. `charly config` performs a hard check after resolving all env vars — if any required var is missing, it aborts before writing the quadlet and prints clear instructions:

```
Error: openwebui requires the following environment variable(s):

  WEBUI_ADMIN_EMAIL — Admin email — pass via: charly config openwebui -e WEBUI_ADMIN_EMAIL=you@example.com

Set them with -e flags, --env-file, or charly.yml env:

  charly config openwebui -e WEBUI_ADMIN_EMAIL=...
```

Source: `charly/config_image.go` (`checkMissingEnvRequires`).

## secret_require Enforcement

Parallel to `env_require` but for credential-backed env vars. Layers declare `secret_require` in `charly.yml` (see `/charly-image:layer`). `charly config` resolves each entry from the credential store via `ResolveCredential` and, if any required value is not stored, aborts with a clear remediation message:

```
Error: openwebui requires the following credential-backed secret(s):

  WEBUI_ADMIN_PASSWORD — Initial admin account password for Open WebUI first-run setup

Store them in the credential backend. For each entry:

  charly secrets set charly/secret WEBUI_ADMIN_PASSWORD <value>

Alternatively, pass the value once via -e; it will be auto-imported:

  charly config openwebui -e WEBUI_ADMIN_PASSWORD=...
```

Source: `charly/config_image.go` (`checkMissingSecretRequires`).

## Plaintext-to-Credential Migration Hook

When `charly config <image>` runs, it automatically migrates any existing plaintext `NAME=VAL` entry in `charly.yml`'s `env:` list whose NAME is now declared as `secret_accept` / `secret_require` on the image. The sequence:

1. Scan `dc.Images[deployKey(image, instance)].Env` for names that match `meta.SecretAccepts` / `meta.SecretRequires`
2. For each match: copy the value to the credential store at the layer-declared `(service, key)` path (default `charly/secret/<NAME>`), remove the entry from `dc.Env`, mark the deploy config dirty
3. On first mutation, back up `charly.yml` → `charly.yml.bak.<unix-timestamp>`
4. Persist the cleaned deploy config via `SaveBundleConfig`
5. Log each migrated entry on stderr: `"Migrated plaintext OPENROUTER_API_KEY from charly.yml to credential store (charly/api-key/openrouter)"`

Idempotent — running on a clean host is a no-op. This gives pre-upgrade hosts an automatic one-time cleanup with a rollback point preserved.

Source: `charly/config_secret_migration.go` (`MigratePlaintextEnvSecrets`).

## `-e` Auto-Import for `secret_accept` / `secret_require`

When a `-e NAME=VAL` flag targets an env var declared as `secret_accept` / `secret_require` on the image, `charly config` auto-imports the value into the credential store and strips it from `c.Env` before the plaintext env merge runs. The stderr output shows each imported key:

```
Imported WEBUI_ADMIN_PASSWORD into credential store (charly/secret/WEBUI_ADMIN_PASSWORD)
Imported OPENROUTER_API_KEY into credential store (charly/api-key/openrouter)
```

The normal secret resolution path then picks up the value from the backend on the same `charly config` invocation. First-time setup is a single command; subsequent runs don't need `-e`.

Plain `env_accept` / `env_require` entries are unaffected — their `-e` values continue to flow through the plaintext env merge into `charly.yml` and the quadlet as before.

Source: `charly/config_secret_migration.go` (`scrubSecretCLIEnv`).

## Provides Filtering (env_accept / env_require opt-in)

`env_provide` is the **supply** side of cross-container env discovery. `env_accept` and `env_require` are the **demand** side. The provide-resolution pipeline in `provides.go` intersects the two sets per consumer, so env vars flow through charly.yml's `provides:` section only to consumers that explicitly asked for them.

**Why filtering exists.** Without it, every deployed service would see every other service's `env_provide` — a chrome layer would receive tailscale sidecar `TS_*` vars, a postgres layer would receive ollama's `OLLAMA_HOST`, and the env table would quickly become noise. Explicit opt-in via `env_accept`/`env_require` is how we enforce the principle that services must declare the contracts they rely on.

**Resolution per variable:**

| Consumer declared | Provider deployed | Result |
|---|---|---|
| `env_require: [X]` (no default) | yes (X in `env_provide`) | X resolved, injected via `provides:` |
| `env_require: [X]` (no default) | **no** | **`charly config` aborts with a hard error** |
| `env_require: [X]` with default | no | default used |
| `env_accept: [X]` | yes | X resolved, injected |
| `env_accept: [X]` | no | var silently omitted |
| neither accepts nor requires X | yes | **var is silently dropped** (filtering in action) |
| neither accepts nor requires X | no | nothing happens |

**Sidecar interaction.** Sidecars (e.g., the tailscale sidecar) participate in the same filtering pipeline — their `TS_*` env set is routed to the sidecar container, not auto-merged into the app container. For the app to see anything from the sidecar, it must declare `env_accept: [<var>]` or `env_require: [<var>]`. See `/charly-automation:sidecar` (Environment Contract) for the pattern.

**`--update-all` effect.** When filtering rules change (e.g., a candy adds a new `env_accept` entry), `charly config <any-image> --update-all` re-runs the resolution pipeline for every deployed image and writes updated `provides:` blocks to their quadlets. Propagation is atomic per-image.

Source: `charly/provides.go` (resolution, filtering, `{{.ContainerName}}` templating), `charly/config_image.go` (`injectEnvProvides`, `injectMCPProvides`, `checkMissingEnvRequires`).

## Sidecar Attachment

Attach a sidecar container at deploy time:

```bash
charly config --list-sidecars                    # List built-in sidecar templates
charly config <image> --sidecar tailscale        # Attach tailscale sidecar
charly config <image> --sidecar tailscale \
  -e TS_HOSTNAME=my-app \
  -e "TS_EXTRA_ARGS=--exit-node=<ip> --exit-node-allow-lan-access"
```

- `--sidecar <name>` — Attach sidecar (repeatable). Saved to charly.yml
- CLI `-e` env vars matching sidecar template keys (e.g., `TS_*`) are auto-routed to the sidecar, not the app container
- Generates pod + sidecar + app quadlet files (3 instead of 1)

See `/charly-automation:sidecar` for full sidecar documentation.

## Environment Variable Handling

**Merge behavior (default):** `-e` performs upsert — new vars override existing vars with the same key; existing vars not in the new set are preserved. This means `charly config setup -e HTTP_PROXY=...` adds the proxy without dropping existing vars like `SSH_AUTHORIZED_KEYS`.

**Clean behavior (`-c`):** `-c`/`--clean` replaces the entire env list in charly.yml. Use when you want to reset env vars to exactly what's specified on the command line.

Kong `sep:"none"` on all `-e` flags means commas in values are preserved (no splitting). `NO_PROXY=localhost,127.0.0.1` works correctly as a single env var.

`normalizeNoProxy()` auto-converts semicolons to commas in `NO_PROXY`/`no_proxy` values during env resolution. Legacy semicolon values in charly.yml are auto-healed.

**NO_PROXY enrichment:** When `HTTP_PROXY` or `HTTPS_PROXY` is present, `charly config` automatically appends all deployed container hostnames to `NO_PROXY`. This is necessary because Chrome does not support CIDR ranges in NO_PROXY (unlike curl) — without explicit hostnames, Chrome routes internal traffic like `http://charly-immich-ml:2283` through the external proxy, causing Bad Gateway errors. Applied in both the main config path and `--update-all`. Source: `charly/envfile.go` (`enrichNoProxy`), `charly/deploy.go` (`DeployedContainerNames`).

**Tunnel persistence:** `charly config setup` automatically persists tunnel config from charly.yml back to charly.yml via `saveDeployState`. Tunnel is a deploy-time concern — see `/charly-core:deploy` for tunnel configuration.

**Tunnel is charly.yml-only:** `labels.go:238` deliberately skips parsing the `ai.opencharly.tunnel` OCI image label. Tunnel config is ONLY sourced from `charly.yml`. New instances created with `charly config setup -i <name>` do NOT inherit tunnel config from the base image's charly.yml entry — you must manually add `tunnel: {provider: tailscale, private: all}` to the instance's charly.yml entry, then re-run `charly config setup` to regenerate the quadlet with `ExecStartPost=tailscale serve` commands.

Source: `charly/envfile.go` (`normalizeNoProxy`), `charly/deploy.go` (`mergeEnvVars`, `saveDeployState`), `sep:"none"` in config_image.go/shell.go/commands.go/start.go.

## Cross-References

### Prerequisites

- `/charly-build:pull` — Required before `charly config` can read OCI labels. Remote refs (`@github.com/...`) are rejected with a redirect to `charly box pull`. If the image isn't local, `ExtractMetadata` returns `ErrImageNotLocal` and the CLI prompts for a pull.

### Deploy-mode neighbors

- `/charly-automation:sidecar` — Sidecar containers, pod networking, Tailscale exit nodes, Environment Contract (how sidecars participate in provides filtering)
- `/charly-core:start` — Requires `charly config` first in quadlet mode
- `/charly-core:deploy` — Deploy state file (charly.yml), sidecar pod deployment, tunnel lifecycle, instance tunnel inheritance, resource caps persistence
- `/charly-automation:enc` — Encrypted storage details
- `/charly-build:secrets` — Container secret management, `charly secrets gpg set TS_AUTHKEY`
- `/charly-build:settings` — Runtime settings (engine, run_mode, encrypted_storage_path)
- `/charly-core:service` — Service lifecycle (start, stop, status, logs)
- `/charly-image:layer` — Volume, secret, `env_provide` / `env_require` / `env_accept` declarations, security resource cap fields, `service:` blocks
- `/charly-image:image` — Image composition, inheritance, OCI label emission, tunnel charly.yml-only note (`labels.go:238`)
- `/charly-core:charly-doctor` — Host GPU/device detection driving `appendAutoDetectedEnv()` (DRINODE, HSA_OVERRIDE_GFX_VERSION)
- `/charly-core:shell` — Interactive shells share the same `appendAutoDetectedEnv()` path
- `/charly-selkies:chrome` — Chrome HTTP proxy (`env_accept`), NO_PROXY auto-enrichment, cgroup resource caps
- `/charly-infrastructure:supervisord` — Event listener pattern that pairs with the resource caps
- `/charly-distros:nvidia`, `/charly-distros:rocm` — GPU layers that consume DRINODE auto-injection
- `/charly-selkies:selkies` — Pixelflux DRINODE consumer + ScreenCapture singleton

## When to Use This Skill

**MUST be invoked** when the task involves `charly config` commands, image deployment setup, quadlet generation, sidecar attachment, secret provisioning, encrypted volumes, data seeding, or volume backing configuration. Invoke this skill BEFORE reading source code or launching Explore agents.

**Workflow position:** After build, before start. `charly box build` → `charly config` → `charly start`.

Source: `charly/config_image.go` (command structs), `charly/quadlet.go` (quadlet generation), `charly/deploy.go` (deploy state), `charly/enc.go` (encrypted volumes), `charly/secrets.go` (secret provisioning), `charly/data.go` (data seeding).

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM in vm.yml.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See CLAUDE.md R1–R10.
