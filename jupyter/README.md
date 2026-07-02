# charly-jupyter

MCP server registration for JupyterLab notebook operations with real-time CRDT collaboration.

This plugin exposes 11 MCP tools using the uniform `<noun>_<verb>` naming convention — `notebook_list`, `notebook_create`, `notebook_get`, `notebook_watch`, `notebook_list_users`, `cell_get`, `cell_update`, `cell_insert`, `cell_delete`, `cell_execute`, `room_list` — to Claude Code, routing them to the JupyterLab server running on `http://localhost:8888/mcp`. The server manages CRDT rooms invisibly: every notebook_*/cell_* call auto-attaches to whichever room is open for the path (UI tab, another MCP session, or this one) or creates one if none exists. `room_list` is a read-only diagnostic. The pre-2026-05-06 client-side room management tools (`room_open`, `room_close`, `room_close_all`, `room_pick`) were deleted — clients no longer manage rooms.

## Contents

- `.claude-plugin/plugin.json` — plugin metadata (name, description, version)
- `.mcp.json` — MCP server registration pointing at `http://localhost:8888/mcp`

No skills of its own — the backing documentation lives in `/charly-jupyter:jupyter-mcp` (server implementation) and the three image skills that publish the server.

## Requirements

- A `jupyter` / `jupyter-ml` / `jupyter-ml-notebook` container must be **running** before Claude Code starts. See `/charly-jupyter:jupyter`, `/charly-jupyter:jupyter-ml`, `/charly-jupyter:jupyter-ml-notebook`.
- Claude Code registers MCP servers at **session start**. If the Jupyter container is launched *after* Claude Code, the auto-connect to `http://localhost:8888/mcp` fails silently and the `mcp__jupyter__*` tools will not appear in the session's tool catalog. **Restart Claude Code after the container is up** to pick up the registration. There is no runtime reconnect path today.

## MCP Name Decoupling

The MCP server name `jupyter` is deliberately stable across renames of the underlying layer, Python package, and image. The `/charly-jupyter:jupyter-mcp` skill documents this pattern in detail ("MCP Name Decoupling" section). Short version: `mcp_provide.name: jupyter` in `candy/jupyter/charly.yml` is the service contract — consumers (`hermes`, `openwebui`, this plugin's `.mcp.json`) all key off that name, not off the layer/package/image name.

## Related Skills

- `/charly-jupyter:jupyter-mcp` — the MCP server implementation (11 tools, FastMCP + Tornado-ASGI bridge, CRDT integration, auto-attach + canonicalization design principles)
- `/charly-jupyter:jupyter` — lightweight parent layer (composes `jupyter-mcp`)
- `/charly-jupyter:jupyter-ml` — GPU ML parent layer (composes `llama-cpp`, `unsloth`, `jupyter-mcp`)
- `/charly-jupyter:jupyter` — lightweight CPU image
- `/charly-jupyter:jupyter-ml` — GPU image
- `/charly-jupyter:jupyter-ml-notebook` — GPU image + seeded finetuning/ollama/openrouter/llms_on_supercomputers notebooks
- `/charly-hermes:hermes` — another MCP consumer that discovers the `jupyter` server via cross-container `env_provide` / `mcp_provide`
- `/charly-build:charly-mcp-cmd` — the declarative `mcp:` check verb for probing this MCP server directly (run via `charly check live jupyter --filter mcp`, served out-of-process by candy/plugin-mcp, exercising the candy's `mcp: ping`/`mcp: list-tools`/`mcp: call` steps). Useful for diagnosing whether a failed `mcp__jupyter__*` tool call is a server issue or a Claude Code session-registration issue.
