---
name: new
description: |
  Scaffold new candies, boxes, and whole projects with template files.
  MUST be invoked before any work involving: charly box new {project, box, candy} commands, creating new projects/boxes/candies, or scaffolding directories.
---

# charly box new -- Scaffold New Projects, Boxes, and Candies

The `charly box new` family groups three scaffolding verbs. See `/charly-image:image` for the full family overview and `/charly-image:layer` for the layer-authoring verb catalog it bootstraps.

## Overview

Three verbs, in decreasing scope:

| Verb | What it creates |
|---|---|
| `charly box new project <dir>` | A fresh `charly.yml` (with `discover: [box, candy]`), empty `box/` + `candy/` directories, and a `.gitignore` |
| `charly box new box <name>` | A new discovered image at `box/<name>/charly.yml` (a `candy:` image doc — kind-keyed `candy:` carrying `base:`; there is no `box:` KIND) |
| `charly box new candy <name>` | A new layer candy at `candy/<name>/charly.yml` (stub kind-keyed `candy:` doc, no `base:`/`from:`) |

All three are **comment-preserving**: the YAML edits route through the `yaml.v3` Node API rather than the value API, so human-authored comments and key order survive round trips. Implementation lives in `charly/scaffold_project.go` + `charly/yaml_setter.go`.

Each verb also auto-becomes an MCP tool (`box.new.project`, `box.new.box`, `box.new.candy`) via Kong reflection in `charly/mcp_server.go` — so an LLM agent driving `charly mcp serve` can scaffold a project from scratch over RPC. See `/charly-build:charly-mcp-cmd` "Authoring tools".

## Quick Reference

| Action | Command | Description |
|--------|---------|-------------|
| New project | `charly box new project <dir>` | Scaffold a fresh charly project (charly.yml + box/ + candy/ + .gitignore) |
| New box | `charly box new box <name> --base <ref> [--candies a,b,c]` | Write box/<name>/charly.yml |
| New candy | `charly box new candy <name>` | Create candy/<name>/charly.yml |

## Usage

### `charly box new project <dir>`

```bash
charly box new project ~/my-project
# Creates:
#   ~/my-project/charly.yml  (version + discover: [box, candy] + defaults)
#   ~/my-project/box/         (empty — boxes discovered per-dir)
#   ~/my-project/candy/       (empty — candies discovered per-dir)
#   ~/my-project/.gitignore   (ignores .build/ + editor scratch files)
```

**A scaffolded project is immediately usable.** The default distro/builder/init/resource
build vocabulary (and the default sidecar templates) are EMBEDDED in the `charly` binary
(`charly/charly.yml`, `//go:embed`) — no build vocabulary to copy or `format_config` to wire. Declare
`distro:`/`builder:`/`init:`/`resource:` in `charly.yml` (or an imported vocab file) ONLY to
extend or override the embedded default. Add a box with `charly box new box <name>`
(writes `box/<name>/charly.yml`) and a candy with `charly box new candy <name>` (writes
`candy/<name>/charly.yml`).

### `charly box new box <name>`

```bash
charly -C ~/my-project box new box hello \
    --base quay.io/fedora/fedora:43 \
    --candies sshd,tmux
# Writes box/hello/charly.yml (an image = a `candy:` node carrying `base:`):
#   candy:
#     name: hello
#     base: quay.io/fedora/fedora:43
#     candy: [sshd, tmux]
```

Flags: `--base` (required — URL or name of another box), `--candies` (optional comma-separated candy names). Existing `charly.yml` comments + key order are preserved.

### `charly box new candy <name>`

```bash
charly -C ~/my-project box new candy sshd
# Creates:
#   ~/my-project/candy/sshd/
#   ~/my-project/candy/sshd/charly.yml  (stub: candy name + version, ready for add-rpm)
```

Follow up with `charly candy add-rpm sshd openssh-server openssh-clients` (see `/charly-image:layer`) to populate packages without manually editing YAML — it creates the `distro.fedora.package` section on demand (and `add-deb` / `add-pac` / `add-aur` the matching `distro.'debian,ubuntu'` / `distro.arch` / `distro.arch.aur` sections).

## Workflow

The end-to-end scaffold → build flow:

1. `charly box new project ~/my-project` — create the project skeleton
2. (optional) Declare `distro:`/`builder:`/`init:`/`resource:` only to EXTEND or OVERRIDE the embedded build vocabulary — a fresh project needs none
3. `charly box new candy my-svc` — create a candy
4. `charly candy add-rpm my-svc openssh-server` — populate packages (see `/charly-image:layer`)
5. `charly box new box my-app --base quay.io/fedora/fedora:43 --candies my-svc` — wire into charly.yml
6. `charly box validate` — check for errors
7. `charly box build my-app` — build the image

All six steps are also callable as MCP tools (`box.new.project`, `box.new.candy`, `candy.add-rpm`, …), so an agent driving `charly mcp serve` can run this entire flow over RPC. See `/charly-build:charly-mcp-cmd` "Authoring tools" for the worked MCP-only example.

The scaffolded `charly.yml` from step 3 is minimal (a `candy:` block with `name:` + `version:` and a placeholder comment). Add sections as needed: a `distro:` map (per-distro `package:` lists, populated by `charly candy add-rpm` / `add-deb` / `add-pac` / `add-aur`) for system packages, `env:` for runtime environment, `port:` / `service:` / `volume:` for services, and `task:` for install operations (mkdir, copy, write, download, link, setcap, cmd, build). The scaffolder does not create separate Taskfile shell scripts — all install logic flows through `task:` in `charly.yml`.

## Naming Rules

- Lowercase-hyphenated names only (e.g., `my-tool`, `dev-tools`)
- Must not conflict with existing layer names

## Project directory override

`charly box new candy <name>` writes into `candy/<name>/` relative to `os.Getwd()`. Override with `-C <dir>` / `--dir <dir>` / `CHARLY_PROJECT_DIR=<dir>`. See `/charly-image:image` "Project directory resolution".

## Cross-References

### `charly box` family siblings

- `/charly-image:image` -- Family overview + charly.yml composition reference
- `/charly-build:build` -- Build images containing the new candy
- `/charly-build:generate` -- Containerfile generation
- `/charly-build:inspect` -- Inspect built image including the new candy
- `/charly-build:list` -- Enumerate layers (the new one shows up here)
- `/charly-build:merge` -- Post-build layer consolidation
- `/charly-build:pull` -- Pull prebuilt images (unrelated; for consumers of your new candy)
- `/charly-build:validate` -- Validate candy and box definitions

### Related skills

- `/charly-image:layer` -- Layer authoring guide, charly.yml format, install files + the `charly candy set / add-rpm / add-deb / add-pac / add-aur` editing surface
- `/charly-build:charly-mcp-cmd` -- "Authoring tools" table + the MCP-only build-from-scratch worked example
- `/charly-internals:go` -- Implementation notes: the `yaml.v3` Node API is the reason edits preserve comments; `charly/scaffold_project.go` + `charly/yaml_setter.go` house the logic
