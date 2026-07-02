---
name: jupyter
description: |
  Lightweight JupyterLab with real-time collaboration on port 8888. No GPU required.
  Based on fedora (not nvidia), supports both amd64 and arm64.
  MUST be invoked before building, deploying, configuring, or troubleshooting the jupyter box.
---

# jupyter

Lightweight JupyterLab with real-time collaboration via jupyter-collaboration (Y-CRDT).

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | agent-forwarding, jupyter (sub-candies: jupyter-mcp), notebook-templates, dbus, charly |
| Platforms | linux/amd64, linux/arm64 |
| Ports | 8888 |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

1. `fedora` (Fedora 43 base — no GPU)
2. `pixi` → `python` → `supervisord` (transitive)
3. `jupyter` — JupyterLab + jupyter-collaboration + data science (composes `jupyter-mcp` sub-candy for MCP extension)
4. `notebook-templates` — Starter notebooks (data candy, seeds /workspace)
5. `agent-forwarding` — SSH/GPG agent forwarding
5. `dbus` — D-Bus session bus
6. `charly` — charly CLI binary

## Ports

| Port | Service | Protocol |
|------|---------|----------|
| 8888 | JupyterLab | HTTP |

## Volumes

| Name | Path | Purpose |
|------|------|---------|
| workspace | /workspace | Persistent notebook storage |

## Quick Start

```bash
charly box build jupyter
charly config jupyter
charly start jupyter
# Open http://localhost:8888
```

Routine ops once started:

```bash
charly status jupyter         # state + tools probe (dbus / charly / supervisord)
charly restart jupyter        # atomic systemctl --user restart (preserves
                          # ExecStopPost → ExecStartPost order — important
                          # when the deploy carries a tailscale tunnel)
charly stop jupyter           # stop without restarting
charly logs jupyter           # supervisord aggregated stdout/stderr
```

## What's Installed

Beyond the JupyterLab core, the box's pixi env carries: pandas /
polars / numpy / scipy / scikit-learn / matplotlib / seaborn for data
work; pyarrow / duckdb for column-store interop; **spacy 3.8.x +
`en_core_web_sm`** for NLP (tokenization, NER, POS, dependency
parsing); black / pytest / graphviz / pyyaml / tqdm as utilities. Full
list and version pins live in `candy/jupyter/pixi.toml` — see
`/charly-jupyter:jupyter` for the package matrix.

## Key Candies

- `/charly-jupyter:jupyter` — JupyterLab + collaboration + data science
- `/charly-distros:agent-forwarding` — SSH/GPG forwarding

## Related Boxes

- `/charly-jupyter:jupyter-ml` — GPU-accelerated variant (nvidia base, full ML stack)
- `/charly-jupyter:jupyter-ml-notebook` — GPU variant with fine-tuning notebooks
- `/charly-openwebui:openwebui` — Open WebUI consumes jupyter for code execution and MCP tools
- `/charly-hermes:hermes` — Hermes agent consumes jupyter MCP for notebook manipulation
- `/charly-distros:fedora` — parent base image

## MCP Server (Programmatic Notebook Access)

The box includes a built-in MCP server at `http://localhost:8888/mcp` (Streamable HTTP transport, MCP spec 2025-11-25). You can create, read, edit, execute, and watch notebooks programmatically — with changes syncing live to all collaborators via CRDT.

The MCP server name is set via the `MCP_SERVER_NAME` environment variable (default: `jupyter`). For multi-instance deployments, override per-instance: `charly config jupyter -i work -e MCP_SERVER_NAME=jupyter-work`.

### Configure Claude Code

There are three supported ways to give Claude Code access to the
jupyter MCP server. Pick whichever matches the scope you want:

**Project-scoped `.mcp.json` (preferred for `claude -p` from a
specific working directory).** Drop a file at `<project-root>/.mcp.json`
with the canonical shape:

```json
{
  "mcpServers": {
    "jupyter": {
      "type": "http",
      "url": "http://localhost:8888/mcp"
    }
  }
}
```

Whenever `claude` (interactive) or `claude -p` (print mode) launches
from that project root, it discovers the file and registers `jupyter`
as an HTTP MCP server. Typical layout: a workspace dir on the host
that is also bind-mounted as the jupyter `workspace` volume — running
`claude -p` from inside that dir lets the model both see the notebook
files on disk AND drive jupyter via MCP. (See `/charly-core:deploy` for the
`--bind workspace=…` flag that pins the volume to a host path.)

**`claude mcp add` shorthand** — equivalent to writing the file
yourself:

```bash
claude mcp add --transport http --scope project jupyter http://localhost:8888/mcp
```

**The `charly-jupyter` plugin** (`plugins/charly-jupyter/.mcp.json`) — declares
the same server at the project level for the opencharly repo itself.
Suitable when you're working IN the opencharly checkout (the file is
gitignored downstream of `.claude-plugin/plugin.json`).

**Container must be running BEFORE `claude` starts.** Claude Code
discovers MCP servers at session-start time. If `charly-jupyter.service`
is not running when `claude` launches, the server registration shows
"failed to connect" and `claude` will not auto-reconnect mid-session.
Start jupyter first, then start the claude session:

```bash
charly status jupyter | grep -q running || charly start jupyter
sleep 3                             # let supervisord settle
cd <workspace-with-.mcp.json>
claude                              # or claude -p "..."
```

If you start `claude` first and then `charly start jupyter`, you'll need
to exit and restart the claude session before the jupyter MCP tools
become available.

### 11 MCP tools (`<noun>_<verb>` form)

| Category | Tools |
|----------|-------|
| Notebook management | `notebook_list`, `notebook_create`, `notebook_get`, `notebook_watch`, `notebook_list_users` |
| Cell operations (CRDT) | `cell_get`, `cell_update`, `cell_insert`, `cell_delete`, `cell_execute` |
| Read-only diagnostic | `room_list` |

**Clients do not manage CRDT rooms.** The server auto-attaches each notebook_*/cell_* call to whichever room exists for that path (UI tab, another MCP session, or this one), or creates a fresh room if none exists. Idle rooms are flushed and closed by a server-side sweeper after `MCP_ROOM_IDLE_TIMEOUT_SEC` (default 600s).

See `/charly-jupyter:jupyter-mcp` "Usage philosophy and caveats" for the full design principles + caveats. See `/charly-jupyter:jupyter` for full parameter and return type documentation.

### Testing with `claude -p`

```bash
# Prerequisites: charly start jupyter

# Create and work with a notebook. The server auto-attaches on every
# cell_*/notebook_* call — no client-side room management needed.
claude -p "Call notebook_create with path 'test.ipynb'"
claude -p "Call cell_insert with path 'test.ipynb', index 0, source 'print(42)', cell_type 'code'"
claude -p "Call cell_execute with path 'test.ipynb' and index 0"
claude -p "Call notebook_get with path 'test.ipynb'"   # outputs persisted via in-place CRDT
```

### Multi-client collaboration

Multiple `claude -p` sessions (or any MCP client) can edit the same notebook simultaneously. Each session creates a separate HTTP connection but shares the same CRDT document. Changes from one client are immediately visible to all others.

```bash
# Client A watches for changes
claude -p "Call notebook_watch with path 'test.ipynb' and timeout 30" &

# Client B makes a change
claude -p "Call cell_update with path 'test.ipynb', index 0, source 'print(\"hello\")'"

# Client A's notebook_watch returns: {"changed": true, "cell_count": 1}
```

## Verification

After `charly start` (or `charly restart` to recycle a running container):

```bash
# Container and services running
charly status jupyter
charly service status jupyter

# Atomic restart (preserves ExecStopPost → ExecStartPost order; important
# when the deploy carries a tailscale tunnel — the off/on sequence
# must be tight to avoid a serve-without-listener window)
charly restart jupyter

# JupyterLab responds
curl -s -o /dev/null -w '%{http_code}' http://localhost:8888    # 200

# MCP server responds
curl -s http://localhost:8888/mcp -X POST \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}'
# Expected: SSE response with serverInfo.name = "jupyter"

# Server extensions
charly shell jupyter -c "jupyter server extension list 2>&1 | grep -E 'ydoc|colab_mcp'"
# Expected: jupyter_server_ydoc enabled OK, jupyter_mcp 0.1.0 OK

# In-container PATH includes the pixi env (the pixi runtime env
# flows through the BUILDER, not the LAYER)
charly shell jupyter -c 'echo PATH=$PATH'
# Expected: PATH starts with /home/user/.pixi/bin:/home/user/.pixi/envs/default/bin:...

# spacy + en_core_web_sm load (the `context: [build]` scenario step, runnable
# at runtime too)
charly shell jupyter -c '~/.pixi/envs/default/bin/python -c "import spacy; spacy.load(\"en_core_web_sm\"); print(\"ok\")"'
# Expected: ok

# MCP tools via Claude Code (run from a dir with .mcp.json)
claude mcp list    # Should show: jupyter: http://localhost:8888/mcp (HTTP) - ✓ Connected
```

## Testing Collaboration

To test real-time collaboration, deploy `sway-browser-vnc` alongside (`charly start sway-browser-vnc`).

Author the browser leg as `cdp:` plan steps (the `cdp:` verb is served
out-of-process by candy/plugin-cdp) and run them with `charly check live
sway-browser-vnc --filter cdp`:

```yaml
# Open JupyterLab in two Chrome tabs via container DNS (two cdp: open steps):
collab-tab-1:
    run: open JupyterLab in tab 1
    cdp: open
    context: [deploy]
    url: http://charly-jupyter:8888/lab
collab-tab-2:
    run: open JupyterLab in a second tab
    cdp: open
    context: [deploy]
    url: http://charly-jupyter:8888/lab
```

**Executing cells via CDP:** Use `Input.dispatchKeyEvent` (not VNC keys — unreliable when Chrome lacks compositor focus). Focus the cell with a `cdp: eval` step, then send Shift+Enter with `cdp: raw` steps:

```yaml
cell-focus:
    run: focus the input cell
    cdp: eval
    context: [deploy]
    tab: "1"
    expression: "document.querySelector('.jp-Cell-inputArea .cm-content')?.focus()"
cell-shift-enter-down:
    run: Shift+Enter keyDown
    cdp: raw
    context: [deploy]
    tab: "1"
    expression: |
        Input.dispatchKeyEvent {"type":"rawKeyDown","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13,"modifiers":8}
cell-shift-enter-up:
    run: Shift+Enter keyUp
    cdp: raw
    context: [deploy]
    tab: "1"
    expression: |
        Input.dispatchKeyEvent {"type":"keyUp","windowsVirtualKeyCode":13,"nativeVirtualKeyCode":13,"modifiers":8}
```

## Test Coverage

Latest `charly check live jupyter` run: **29 passed, 0 failed, 0 skipped**.
All scenario steps embedded in the `ai.opencharly.description` OCI label:
jupyter-lab binary under pixi, notebook-templates provisioned into
`/workspace`, jupyter-mcp extension enabled, fastmcp pip
package installed. `context: [deploy]` steps: supervisord up, port 8888 reachable
on `127.0.0.1`, `/api` returns 200 with `version` in body, `/mcp`
returns 400 on empty POST (proving MCP routing is wired). `context: [build]` steps:
`jupyter_mcp` appears in extension list, workspace has ≥1 `.ipynb`.

See `/charly-check:check` for the framework and author-facing gotchas.

## Related Skills

- `/charly-jupyter:jupyter`, `/charly-jupyter:jupyter-mcp`, `/charly-jupyter:notebook-templates`
- `/charly-check:check` — declarative testing framework
- `/charly-core:charly-config` — deploy setup
- `/charly-build:charly-mcp-cmd` — the box inherits 3 `context: [deploy]` `mcp:` scenario steps from the `jupyter` candy (`ping`, `list-tools` asserting all 11 prefixed tool names, `call notebook_list`). Run `charly check live jupyter --filter mcp` to exercise them against a live deployment
- `/charly-jupyter:jupyter-ml`, `/charly-jupyter:jupyter-ml-notebook` — GPU variants that inherit the same MCP test suite

## When to Use This Skill

**MUST be invoked** when the task involves the jupyter box, collaborative Jupyter notebooks, lightweight Jupyter deployments without GPU, MCP-based notebook access, or multi-client collaboration. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
