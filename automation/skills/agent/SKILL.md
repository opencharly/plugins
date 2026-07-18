---
name: agent
description: Operate and diagnose Charly's daemon-free agent control plane, including sessions, runs, terminal channels, Pi native/orchestrator/TUI modes, tmux compatibility, federation, generic local/deployment/SSH/gRPC routes, transient Charly endpoint replication, incidents, RCA, and recovery. Use whenever a task invokes or modifies `charly agent`, `charly tui`, `charly tmux`, agent MCP tools, or agent target routing.
---

# Charly agent control

Use Charly commands as the operational API. Do not replace them with direct container-engine or ad-hoc tmux commands. Filesystem inspection and a debugger are diagnostic fallbacks after Charly's status, logs, transcripts, incidents, and check reports have been collected.

## Discover capabilities

```bash
charly agent runtime list
charly agent runtime status pi --class agent-runtime
charly agent runtime status tmux --class terminal
charly agent profile list
```

Runtime names select providers, never transports. The same provider receives a CUE-validated `#TargetSpec` over `Provider.Channel` for every placement.

## Sessions and runs

```bash
SESSION=$(charly agent session create pi | jq -r .id)
charly agent run start "$SESSION" 'review the current changes'
charly agent session show "$SESSION"
charly agent run list
```

Use `pi` for the native SDK runner. Set the documented orchestrator environment when compatibility with the separately installed official Pi orchestrator is required; Charly delegates the exact `rpc-stream` byte stream. Use the ordinary `pi` terminal profile with runtime `tmux` when Pi must live inside a persistent terminal. `charly tui` is a client of the same persisted control plane, not a separate runtime.

## Generic target routes and endpoint bootstrap

Targets may be shorthand (`deployment`, `user@host:port::deployment`) or `#TargetSpec` JSON:

```bash
TARGET='{"hops":[{"transport":"ssh","address":"box","user":"agent"},{"transport":"grpc"},{"transport":"tmux"}]}'
charly agent terminal run pi --target "$TARGET"

TARGET='{"deployment":"toolbox","hops":[{"transport":"ssh","address":"inner"},{"transport":"grpc"},{"transport":"tmux"}]}'
charly agent terminal run codex --target "$TARGET"
```

Every accessible deployment or SSH node works whether Charly is installed or not. The controller probes the target, keeps an equal/newer packaged Charly, or replicates its active binary through `kit.EnsureCharlyInDeployVenue` to `/tmp/charly-<calver>` and invokes that explicit path. It never changes target PATH and never downgrades a package. This bootstrap repeats recursively at every process/gRPC boundary, so exec, deployment, SSH, gRPC, and tmux compose without pair-specific code.

## Typed terminals

```bash
RUN=$(charly agent terminal launch codex --target "$TARGET" | jq -r .run_id)
charly agent terminal input codex 'inspect the failing test' --target "$TARGET" --run-id "$RUN" --paste
charly agent terminal key codex enter --target "$TARGET" --run-id "$RUN"
charly agent terminal snapshot codex --target "$TARGET" --run-id "$RUN"
charly agent terminal transcript "$RUN"
charly agent terminal attach codex --target "$TARGET" --run-id "$RUN"
charly agent terminal close codex --target "$TARGET" --run-id "$RUN"
```

Use `charly tmux` only as the compatibility facade for named shell sessions. It still calls the typed terminal controller and does not construct remote tmux shell commands.

## Federation, incidents, RCA, and recovery

```bash
charly agent federation run user@box tmux 'inspect the target' --profile codex
charly agent federation list
charly agent incident list
charly agent incident show INCIDENT_ID
charly agent rca start INCIDENT_ID
charly agent rca complete RCA_ID --root-cause 'specific cause' --finding 'evidence-backed finding'
charly agent recovery decide INCIDENT_ID --rca RCA_ID --action operator
charly agent recovery apply DECISION_ID
```

Never retry an agent failure automatically. Record the incident, collect ordered transcript/channel evidence, complete RCA, and apply an explicit recovery decision. Emergency abort is the only pre-RCA exception and must preserve the unresolved incident.

## Diagnostics contract

- Expect phase/status events such as endpoint bootstrap, `waiting-for-prompt`, `prompt-ready`, running/reattached, settled, and exit.
- Treat silence, malformed frames, EOF before ACK, cleanup failure, warnings, and unexpected duration as incidents.
- Use no sleep, polling loop, backoff, or arbitrary timed retry. Synchronize on process, tmux control, gRPC, terminal, and context events.
- Preserve stdout for structured command results and use stderr for provider/operation/target progress and actionable failures.
- For implementation acceptance, run the complete unmodified disposable R10 bed with `charly check run <bed>` and use its per-step logs and summary.

## Related skills

- `/charly-automation:tmux` — terminal-provider and compatibility details.
- `/charly-check:check` — full R10 workflow.
- `/charly-internals:go` — provider placement and generated wire contracts.
- `/charly-internals:root-cause-analyzer` — mandatory failure analysis.
