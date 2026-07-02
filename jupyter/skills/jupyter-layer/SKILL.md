---
name: jupyter-layer
description: |
  Lightweight JupyterLab with real-time collaboration (jupyter-collaboration) on port 8888.
  No GPU required. Use when working with collaborative notebooks, jupyter-collaboration,
  or lightweight Jupyter environments without ML/CUDA dependencies.
---

# jupyter -- Lightweight JupyterLab with real-time collaboration

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Sub-candies | `jupyter-mcp` |
| Ports | 8888 |
| Service | `jupyter` (supervisord) |
| Volume | `workspace` at `/workspace` |
| MCP provides | `jupyter` at `http://{{.ContainerName}}:8888/mcp` (streamable HTTP) |
| Install files | `charly.yml` (rpm: git), `pixi.toml` |

## Key Packages

**conda-forge:** JupyterLab >= 4.4.0, ipywidgets, ipykernel, jupyterlab-git, jupyter-resource-usage, matplotlib, seaborn, pandas, numpy, scikit-learn, scipy, polars, pyarrow, duckdb, **spacy**, **spacy-model-en_core_web_sm**, black, pytest, graphviz, pyyaml, tqdm

**PyPI:** jupyter-collaboration >= 4.1.0

**RPM:** git

### NLP

`spacy` (3.8.x) ships with the small English statistical model
(`en_core_web_sm`) preloaded so notebooks can do tokenization, NER,
dependency parsing, and POS tagging out-of-the-box without a
post-deploy `python -m spacy download` step. Sample:

```python
import spacy
nlp = spacy.load("en_core_web_sm")
doc = nlp("Apple is looking at buying a U.K. startup for $1 billion")
[(t.text, t.pos_) for t in doc]   # tokens + parts of speech
[(e.text, e.label_) for e in doc.ents]  # named entities
```

The `spacy-import` build-context `check:` step (a deterministic Op in
the `plan:`) verifies the package + model load
successfully on every image build — a future upstream rename or version
bump that breaks the model load fails the build loudly.

## Environment

No custom environment variables on the candy itself. **Runtime PATH
contributions** for the pixi env (`~/.pixi/bin`,
`~/.pixi/envs/default/bin`) and cache dirs (`PIXI_CACHE_DIR`,
`RATTLER_CACHE_DIR`) come from the **pixi BUILDER** (declared in the
embedded `builder:` vocabulary (`charly/charly.yml`) under
`builder.pixi.runtime_env:` and
`path_contributions:`) — see `/charly-internals:generate-source` for the
`writeCandyEnv` flow. The pixi runtime env flows through the pixi
BUILDER (not the pixi LAYER) so boxes that consume pixi via
pixi.toml-triggered builds (jupyter, openwebui, immich-ml, …) get the
env contract automatically without needing pixi as a top-level candy
for sibling-grouped auto-intermediate inheritance.

## Collaboration

Real-time collaborative editing via [jupyter-collaboration](https://github.com/jupyterlab/jupyter-collaboration) (Y-CRDT). Multiple users editing the same notebook see shared cursors and live changes. The backend uses `jupyter_server_ydoc` with `pycrdt-websocket` for CRDT synchronization. No external database required — document state is managed in-memory by default, with optional SQLite persistence.

Collaboration is **enabled by default** when jupyter-collaboration is installed. The WebSocket endpoint at `/api/collaboration/room/` handles document sync.

## Token Authentication

The service supports optional token-based authentication via the `JUPYTER_TOKEN_FILE` environment variable. If set and the file exists, its contents are used as the auth token. Otherwise, authentication is disabled (empty token, no password) for development convenience.

## Volume

The `workspace` volume is mounted at `/workspace`. JupyterLab serves notebooks from this directory via `--notebook-dir=/workspace`.

## Usage

```yaml
# charly.yml
jupyter:
  base: fedora
  candy:
    - agent-forwarding
    - jupyter
    - dbus
    - charly
  ports:
    - "8888:8888"
```

## Differences from jupyter-ml Layer

| | jupyter | jupyter-ml |
|---|---|---|
| Base dependency | `supervisord` | `cuda`, `supervisord` |
| GPU | No | CUDA required |
| Platforms | amd64 + arm64 | amd64 only |
| Focus | Collaboration + data science | ML/AI training |
| Key packages | jupyter-collaboration, pandas, polars | PyTorch, vLLM, Unsloth, llama.cpp |
| Image size | ~3.4 GB | ~15+ GB |

## MCP Server Discovery

The `jupyter` candy declares `mcp_provide` for cross-container and pod MCP discovery. The URL template `http://{{.ContainerName}}:8888/mcp` resolves to the actual container name at deploy time (e.g., `http://charly-jupyter:8888/mcp`), or to `http://localhost:8888/mcp` in combined boxes where both services run in the same container.

- **Transport:** Streamable HTTP (`http`)
- **11 tools** available via the `jupyter-mcp` extension (see below)
- **Hermes auto-configures** via the `CHARLY_MCP_SERVERS` env var -- no manual MCP registration needed
- **Pod-aware:** resolves to `localhost` in combined boxes where hermes and jupyter share a container

## MCP Server Extension (`jupyter_mcp`)

The candy includes a built-in MCP (Model Context Protocol) server at `/mcp` on port 8888. You can create, read, edit, and execute notebook cells programmatically — with changes syncing live to all connected JupyterLab clients via CRDT.

### Architecture

```
Tornado (Jupyter Server, :8888)
  └── /mcp → TornadoASGIHandler → FastMCP ASGI App (Starlette, in-process)
                                      └── RTCAdapter → YNotebook (CRDT)
```

- **FastMCP v3.x** (standalone, by Prefect) with Streamable HTTP transport (MCP spec 2025-11-25)
- **Tornado-ASGI bridge** — custom handler translates Tornado requests to ASGI scope/receive/send (both share the same asyncio event loop)
- **Auto-attach + path canonicalization** — every `notebook_*`/`cell_*` call routes through `_resolve_notebook_doc(canonical_path)` which attaches to whichever room exists for the deterministic `room_id` (UI tab, another MCP session, this one) or creates one. Single room per notebook is an enforced invariant.
- **In-place `set_cell`** — cell mutations operate on the existing Y.Map's `source`/`metadata`/`outputs` IN PLACE, preserving the cell's `id` and its position in the underlying `Y.Array`.
- **Per-notebook asyncio locks** — serializes mutations on the same notebook to prevent index-based race conditions during concurrent access
- **Server-side idle-room sweeper** — periodically flushes and closes rooms with zero clients idle for `MCP_ROOM_IDLE_TIMEOUT_SEC` (default 600s)
- **Lazy YDocExtension resolution** — resolved on first tool call, not at extension load time (avoids load-order dependency)

### MCP Tools (11 total — `<noun>_<verb>` form)

Clients do not manage CRDT rooms. The server auto-attaches every `notebook_*`/`cell_*` call to whichever room exists, or creates one. See `/charly-jupyter:jupyter-mcp` "Usage philosophy and caveats".

**Notebook operations:**
| Tool | Parameters | Returns |
|------|-----------|---------|
| `notebook_list` | — | `[{"path": "...", "name": "..."}]` |
| `notebook_create` | `path` | `{"path": "...", "name": "..."}` (no room opened — auto-attach happens on first cell op) |
| `notebook_get` | `path` | Full notebook dict (live CRDT; auto-attaches) |
| `notebook_watch` | `path`, `timeout=30` | `{"changed": true, "cell_count": N}` or `{"changed": false}` (auto-attaches) |
| `notebook_list_users` | `path` | `[{"id": "...", "name": "..."}]` — awareness users on ONE notebook (read-only; returns `[]` if no room) |

**Cell Operations (CRDT — changes sync live to all collaborators; auto-attach):**
| Tool | Parameters | Returns |
|------|-----------|---------|
| `cell_get` | `path`, `index` | Cell dict (source, cell_type, metadata, outputs) |
| `cell_update` | `path`, `index`, `source`, `cell_type?` | `"Cell N updated"` — preserves cell `id` (in-place Y.Map mutation) |
| `cell_insert` | `path`, `index`, `source`, `cell_type="code"` | `"Cell inserted at index N"` |
| `cell_delete` | `path`, `index` | `"Cell N deleted"` |
| `cell_execute` | `path`, `index` | `[{"type": "stream", "content": {...}}]` — also writes `outputs` + `execution_count` back via the in-place `set_cell` path |

**Read-only diagnostic (no mutation, no auto-attach):**
| Tool | Parameters | Returns |
|------|-----------|---------|
| `room_list` | — | `[{"room_id": ..., "path": ..., "file_id": ..., "users": [...], "user_count": N, "has_kernel": bool}, ...]` — verify the single-room invariant: never two rows for the same path |

### Installation

The MCP extension is installed by the `jupyter-mcp` sub-candy (composed via `candy: [jupyter-mcp]`):
1. `pip install "fastmcp>=3.2.0"` + opentelemetry runtime deps (not pixi -- cross-platform resolver conflicts with opentelemetry-api on aarch64)
2. `pip install --no-deps /ctx/jupyter_mcp` (extension package from sub-candy directory)
3. Extension enabled via `jupyter_server_config.d/jupyter_mcp.json`

### Source files

```
candy/jupyter-mcp/
├── jupyter_mcp/
│   ├── pyproject.toml              # hatchling package, no deps (--no-deps install)
│   └── jupyter_mcp/
│       ├── __init__.py             # Extension entry point
│       ├── app.py                  # Registers /mcp handler + ASGI lifespan
│       ├── tornado_asgi.py         # Tornado↔ASGI bridge (SSE streaming, disconnect handling)
│       ├── mcp_server.py           # FastMCP tool definitions (11 tools)
│       └── rtc_adapter.py          # CRDT access via YNotebook + kernel execution
# (in charly.yml tasks:)  # Build-time: pip install fastmcp + extension + enable
└── charly.yml
```

### Multi-client support

Multiple MCP clients can edit the same notebook simultaneously:
- All sessions share the same CRDT document via the singleton RTCAdapter
- Per-notebook asyncio locks prevent index corruption during concurrent mutations
- `notebook_watch` uses a fan-out `NotebookWatcher` — each watcher gets an independent `asyncio.Event`, signaled when any CRDT change occurs
- The CRDT layer (pycrdt) handles merge conflicts automatically

## Implementation Notes

- The supervisord service command calls `jupyter lab` directly, not via `pixi run`. Pixi multi-stage builds copy only `~/.pixi/envs/` to the final image — `pixi.toml` is not present at runtime.
- The `start-jupyter` pixi task in `pixi.toml` is for build-time verification only.

## Tests

The candy ships its acceptance steps in its `plan:`,
baked into the `ai.opencharly.description` OCI label (see `/charly-check:check`
for the full schema). Each step is one inline Op — a probe is a `check:`
step — tagged with the `context:` axis that selects when it runs:

- **`context: [build]`** (run under `charly check box`):
  - `jupyter-lab-binary` — `${HOME}/.pixi/envs/default/bin/jupyter-lab`
    exists (proves pixi env install succeeded)
  - `spacy-import` — `python -c "import spacy;
    spacy.load('en_core_web_sm')"` exits 0 (proves NLP packages + model
    load successfully)
- **`context: [deploy]`** (run under `charly check live` against a live service):
  - `workspace-dir` — `/workspace` exists (mount visible)
  - `jupyter-service` — supervisord program `jupyter` is RUNNING
  - `jupyter-port` — `${CONTAINER_IP}:${HOST_PORT:8888}` reachable
  - `jupyter-api` — `GET .../api` returns 200 with `"version"` in body
    (the `${HOST_PORT:8888}` substitution means the step works
    unchanged when `charly.yml` remaps the host port)
  - `mcp-jupyter-ping` — MCP server responds to `ping`
  - `mcp-jupyter-list-tools` — assertion that all 11 documented MCP
    tools are present in `tools/list`
  - `mcp-jupyter-call-list-notebooks` — actually invokes
    `notebook_list` and verifies the response shape

## Used In Boxes

- `/charly-jupyter:jupyter`

## Related Candies

- `/charly-jupyter:jupyter-ml` -- GPU-accelerated variant with full CUDA ML stack + same CRDT MCP server
- `/charly-jupyter:jupyter-mcp` -- MCP server implementation (sub-candy, 11 tools for programmatic notebook access using `<noun>_<verb>` naming; clients don't manage CRDT rooms — the server auto-attaches)
- `/charly-jupyter:notebook-templates` -- Starter notebooks (data candy, used alongside this candy in boxes)
- `/charly-hermes:hermes` -- MCP consumer (auto-discovers via `CHARLY_MCP_SERVERS` env var; uses `jupyter` server tools to read/edit/execute cells)
- `/charly-openwebui:openwebui` -- MCP consumer (sets `CODE_EXECUTION_ENGINE=jupyter` when this server is discovered, routing Open WebUI code-block execution into the Jupyter kernel)
- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-languages:python` -- Python runtime (transitive via supervisord)
- `/charly-build:charly-mcp-cmd` -- end-to-end testing of the candy's MCP endpoint via the declarative `mcp:` check verb (`ping`/`list-tools`/`call`, run via `charly check live <image> --filter mcp`); the candy ships 3 deploy-context `mcp:` steps in its `plan:` against `list_notebooks`/`insert_cell`/`execute_cell`

## When to Use This Skill

Use when the user asks about:

- Real-time collaborative Jupyter notebooks
- jupyter-collaboration or Y-CRDT setup
- Lightweight Jupyter without GPU/ML dependencies
- Port 8888 service (check if GPU variant intended)
- The `jupyter` candy
- MCP server for notebook manipulation
- Programmatic notebook access for you
- `watch_notebook` or change notifications
- Multi-client concurrent editing

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
