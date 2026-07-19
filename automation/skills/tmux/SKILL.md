---
name: tmux
description: |
  Typed persistent terminal and terminal-agent sessions backed by isolated tmux control-mode servers.
  Use for local, deployment, SSH, gRPC, nested, detached, reattached, TTY, snapshot, transcript,
  literal-input, paste, key, resize, signal, cleanup, incident, and RCA workflows.
---

# Typed tmux terminal provider

`terminal:tmux` and `agent-runtime:tmux` are generic bidirectional providers. Each run owns an isolated tmux socket derived from its UUIDv7. Charly transports CUE-generated terminal inputs and ordered channel frames; the plugin alone handles tmux control mode, ANSI/alternate-screen emulation, snapshots, pane lifecycle, and safe input translation.

The target-side Charly endpoint must be able to resolve `tmux` on its process `PATH`; Charly itself need not be preinstalled. At every deployment or SSH boundary the controller keeps an equal/newer packaged Charly or copies the active binary through `EnsureCharlyInDeployVenue` to a versioned `/tmp` path, then starts the fixed gRPC endpoint. A named profile is resolved from project candies or the selected deployment image's `ai.opencharly.terminal_profiles` label. An inline `#TerminalProfile` JSON object is also accepted.

## Lifecycle

```bash
RUN=0198f140-6b7a-7b90-8a10-aabbccddeeff
TARGET='{"deployment":"my-agent-box"}'

# Start, confirm the typed running event, and detach.
charly agent terminal launch claude-code --target "$TARGET" --run-id "$RUN"

# Inspect normalized screen state or durable ordered evidence.
charly agent terminal snapshot claude-code --target "$TARGET" --run-id "$RUN"
charly agent terminal transcript "$RUN"

# Typed inputs: literal text, explicit paste, allowlisted key, resize, signal.
charly agent terminal input claude-code 'review the current change' --target "$TARGET" --run-id "$RUN" --paste
charly agent terminal key claude-code enter --target "$TARGET" --run-id "$RUN"
charly agent terminal resize claude-code 160 50 --target "$TARGET" --run-id "$RUN"
charly agent terminal signal claude-code interrupt --target "$TARGET" --run-id "$RUN"

# Real-TTY attachment and explicit cleanup.
charly agent terminal attach claude-code --target "$TARGET" --run-id "$RUN"
charly agent terminal close claude-code --target "$TARGET" --run-id "$RUN"
```

`run` waits for a real pane exit. `launch` returns only after `running` or `reattached`, leaving the run-owned server available. A proven semantic adapter may settle an `agent-runtime:tmux` run while preserving its tmux session for follow-up. A generic profile without an adapter never infers completion from silence; the operator or coordinator explicitly attaches, closes, or waits for exit.

## Generic route composition

The same terminal calls accept every `#TargetSpec`; runtime names never select transport code.

```bash
# Real gRPC/HTTP2 over SSH stdio, with tmux behind that endpoint.
TARGET='{"hops":[{"transport":"ssh","address":"box.example","user":"agent"},{"transport":"grpc"},{"transport":"tmux"}]}'

# Recursive process/gRPC placement before the same terminal provider.
TARGET='{"hops":[{"transport":"ssh","address":"outer"},{"transport":"grpc"},{"transport":"exec"},{"transport":"grpc"},{"transport":"tmux"}]}'

# Place the endpoint in any Charly deployment, then continue through the route.
TARGET='{"deployment":"toolbox","hops":[{"transport":"ssh","address":"inner"},{"transport":"grpc"},{"transport":"tmux"}]}'
```

SSH identity, port, working directory, environment, and deterministic `-o key=value` options are fields on the CUE target hop. SSH is only the process carrier; Provider.Channel remains the wire protocol.

The compatibility command tree uses the same controller:

```bash
charly tmux run toolbox sh --session review
charly tmux cmd toolbox 'printf READY' --session review --no-notify
charly tmux capture toolbox --session review
charly tmux send toolbox 'exit 0' --session review --enter
charly tmux kill toolbox --session review
```

These commands never shell out recursively through `charly cmd`/`charly shell` and never touch an operator's tmux socket.

## Safety and evidence

- Text uses tmux literal input; paste uses a tmux buffer; keys and signals are profile-allowlisted canonical values.
- User content is never interpolated into a shell command.
- Output sequences are monotonic and ACKed; replay buffers are bounded and fail loudly before unacknowledged evidence can be evicted.
- Control disconnect detaches when persistence permits. Initial reattachment and sequence recovery use a structured resynchronization snapshot.
- Normal zero exit or explicit close verifies server cleanup. Nonzero exit, malformed stream, evidence overflow, or cleanup failure creates an incident and performs no automatic restart.
- Recovery requires a completed RCA, except an explicit emergency abort that still records the unresolved incident.
- Semantic readiness is driven by tmux control-output events. `waiting-for-prompt` and `prompt-ready` statuses make the boundary observable; capture polling, sleep, backoff, and timed retries are forbidden.

## Terminal agents

Claude Code, Codex, and Gemini candies publish profiles for `agent-runtime:tmux`. The Pi candy publishes both native `agent-runtime:pi` and an ordinary `pi` terminal profile, so Pi can run directly through its SDK harness or inside tmux without a transport-specific branch.

Create a terminal-backed durable session and run it through the same headless API:

```bash
charly agent session create tmux --profile codex --target '{"deployment":"coder"}'
charly agent run start SESSION_UUID 'inspect the failing test'
```

## Related skills

- `/charly-infrastructure:tmux-layer` — installs tmux in a candybox.
- `/charly-core:shell` and `/charly-core:cmd` — one-shot interactive/synchronous container execution.
- `/charly-check:check` — disposable R10 beds and live evidence requirements.
