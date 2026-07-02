---
name: charly-mcp
description: |
  MCP server exposing the full charly CLI as tools (Streamable HTTP on port
  18765). Meta-layer composition — layers: [charly, supervisord] — ships only
  service wiring + `/workspace` bind-mount + CHARLY_PROJECT_DIR env plumbing.
  Auto-falls back to the upstream opencharly/charly repo when /workspace
  has no charly.yml. Use when composing an MCP gateway into any box so LLM
  agents can drive charly remotely.
---

# charly-mcp -- MCP server deployment layer

## Candy Properties

| Property | Value |
|----------|-------|
| Kind | Meta-layer (no install files of its own) |
| Composition | `candy: [charly, supervisord]` |
| Port | 18765 (Streamable HTTP MCP endpoint at `/mcp`) |
| Service | supervisord-managed `charly-mcp` program |
| Volumes | `project` → `/workspace` (bind-mount the project root from the host) |
| Env | `CHARLY_PROJECT_DIR: "/workspace"` |
| mcp_provide | `{name: charly, url: http://{{.ContainerName}}:18765/mcp, transport: http}` |

**Volume naming note:** the volume NAME is `project` (deployer-facing
API: `charly config <image> --bind project=/path`) but the in-container PATH
is `/workspace` — a neutral term that works regardless of whether the bind
mount is an opencharly checkout or any other dev workspace.

## What It Provides

Deploys `charly mcp serve --listen :18765` inside the container under
supervisord. The server exposes the entire charly CLI (auto-generated from
Kong reflection, currently ~192 tools including the authoring
surface — project scaffolding, YAML editing, file-write verbs) as MCP
over Streamable HTTP. Any box composing `charly-mcp` advertises itself
via the `ai.opencharly.mcp_provide` OCI label, so consumers —
Claude Code, Open WebUI, OpenClaw, or charly's own declarative `mcp:` check verb
— can drive it without any out-of-band URL configuration.

See `/charly-build:charly-mcp-cmd` Part 2 for the full server architecture: Kong
reflection, destructive-hint annotations, `--read-only` filter,
transport dispatch.

## Composition vs. dependency

This candy uses `candy:`, not `require:` — deliberately. The
distinction:

- `require:` says "my install needs these candies installed first."
- `candy:` says "I *am* these candies plus my additions."

`charly-mcp` installs no packages and copies no files — it's pure wiring
(service block, mcp_provide declaration, volumes/env, one mkdir
task to create `/workspace` with 0777 so `charly version` works even
when no bind-mount is attached). A meta-layer composition (`candy:`)
captures that exactly. The validator requires every candy to ship
*something* installable; `candy:` satisfies that by transitively
pulling in the children's install files.

## Three deployment patterns

Build-mode MCP tools (`box.build`, `box.list.boxes`,
`box.inspect`, etc.) need to read `charly.yml`. The charly-mcp candy
supports three paths, in order of "how much local setup":

**1. Bind-mount a local project** (maximal local iteration):

```bash
charly config <image> --bind project=/home/you/opencharly
charly start <image>
```

The agent reads charly.yml + candy/ directly from the host — any
local edit is immediately visible.

**2. Pin a remote repo** (reproducible, no local checkout):

```bash
charly config <image> -e CHARLY_PROJECT_REPO=opencharly/charly@<sha>
charly start <image>
```

At serve-startup, `charly mcp serve` clones into
`~/.cache/charly/repos/github.com/opencharly/charly@<sha>` and chdirs
there. No bind mount needed. Good for CI, headless dev, or shipping
an agent that always drives a specific upstream version.

**3. Auto-fallback** (zero setup — the default):

```bash
charly config <image>
charly start <image>
# Nothing bound to /workspace; /workspace is world-writable but empty.
# charly mcp serve's bootstrapProject() detects no charly.yml in cwd and
# silently clones + chdirs into the default opencharly/charly
# cache. Logs a single line naming the reason.
```

Opt out with `--no-default-repo` (hard-fail instead of falling back).
The top-level charly CLI never auto-fetches — only `charly mcp serve` does.

**How the fallback fires:** this candy's `env:` block permanently sets
`CHARLY_PROJECT_DIR=/workspace`, but `bootstrapProject()` does NOT early-return on
that env being set — it checks for an actual `charly.yml` in the resolved cwd
and falls back to the default repo if missing. That is what makes pattern 3
work by default even though `CHARLY_PROJECT_DIR` is always populated. See
`/charly-build:charly-mcp-cmd` "Project-dir wiring" for the full RCA.

## Tests

Six deploy-scope tests ship with the candy:

| Test | Purpose |
|---|---|
| `charly-mcp-service` | supervisord `charly-mcp` program is running |
| `charly-mcp-port` | host `127.0.0.1:${HOST_PORT:18765}` reachable |
| `mcp-charly-ping` | MCP `ping` succeeds over the in-repo client (URL rewritten via `rewriteMCPURLForHost`, host-networked containers included) |
| `mcp-charly-list-tools` | MCP `list-tools` returns a catalog containing the canonical `box.build`, `status`, `test.mcp.ping` entries |
| `mcp-charly-call-version` | MCP `call version` returns the in-container CalVer (proves round-trip of a safe tool) |
| `mcp-charly-call-list-images` | MCP `call box.list.boxes` returns boxes — **proves the bind-mount OR auto-fallback is working** (matches "fedora" either way, since upstream opencharly/charly always has a `fedora` image) |

All `mcp:` checks pass `mcp_name: charly` so they stay unambiguous on
boxes that also expose `jupyter` or `chrome-devtools` servers
(e.g. `/charly-openclaw:openclaw-desktop`).

## Host networking caveat

Host-networked containers have an empty `NetworkSettings.Ports`. The
`charly/mcp_client.go` `lookupHostPort()` function detects
`HostConfig.NetworkMode == "host"` and returns the container port
verbatim (container ports ARE host ports under `network: host`). See
`charly/checkvars.go` `IsHostNetworked()` + the matching `mergeRuntimeVars()`
handling for `HOST_PORT:<N>` env-var population.

Practical impact: charly-mcp works on both bridge-networked boxes
(e.g. `/charly-coder:charly-arch`) and host-networked ones (e.g.
`/charly-coder:fedora-coder`, `/charly-distros:charly-fedora`).

## Port choice rationale

Default `:18765` chosen for non-collision with sibling MCP candies:

- `8888` — jupyter-mcp
- `9224` — chrome-devtools-mcp (via mcp-proxy)
- `18789` — openclaw gateway

## Used In Boxes

Compose `charly-mcp` into any box that should be reachable as an MCP
gateway. Current users:

- `/charly-coder:fedora-coder` — kitchen-sink dev box; uses pattern 3 (auto-fallback) by default, pattern 1 when the developer wants local edits visible.
- `/charly-coder:charly-arch` — Arch-based charly toolchain box (bridge network, ports 2222/18765).

Boxes composing `charly-mcp` must publish port 18765 (either via
candy-declared `ports: [18765]` that auto-collects into the
container's EXPOSE, or a box-level `ports: ["18765:18765"]` block
in `charly.yml`). Both `network: host` and the default charly bridge work.

## Related Candies

- `/charly-tools:charly` — The underlying binary candy this wraps.
- `/charly-infrastructure:supervisord` — Init system for the `charly-mcp` program.
- `/charly-jupyter:jupyter-mcp` — Sibling MCP server (notebook manipulation, FastMCP-based).
- `/charly-selkies:chrome-devtools-mcp` — Sibling MCP server (browser automation, mcp-proxy wrapper).

## Cross-References

- `/charly-build:charly-mcp-cmd` — **Part 2: Server** is the authoritative reference for `charly mcp serve` architecture, destructive-hint policy, `--read-only` filter, capture model, and the new bootstrapProject() logic.
- `/charly-image:image` — "Project directory resolution" covers the `-C` / `--dir` / `CHARLY_PROJECT_DIR` global flag and `--repo` / `CHARLY_PROJECT_REPO`.
- `/charly-core:charly-config` — `--bind project=<path>` is the deployer's handshake with this candy's `volume:` declaration.
- `/charly-check:check` — Deploy-scope `mcp:` test verb methods used here.
- `/charly-internals:go` — `charly/mcp_server.go` `bootstrapProject()` implementation, including the env-var proxy detection of top-level flags and the unconditional charly.yml check.

## When to Use This Skill

**MUST be invoked** when:

- Adding `charly-mcp` to a box's candy list.
- Debugging why a build-mode MCP tool returns stale data or an unexpected
  box list (is the agent reading the bind-mount or the auto-fallback?).
- Authoring an charly-like CLI's MCP deployment and wanting the reference
  pattern (`candy:` composition + volumes + env + service + auto-fallback).
- Investigating port-18765 collisions or MCP URL rewriting on composed
  boxes (especially host-networked ones).

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
