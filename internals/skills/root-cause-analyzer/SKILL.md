---
name: root-cause-analyzer
description: |
  R1 mandatory failure analysis agent. MUST be invoked before any remediation
  when an unexpected error, warning, or anomaly occurs. Performs the 8-step
  root cause analysis process.
---

# Root Cause Analyzer

## Overview

The root-cause-analyzer is an **enforcer agent** at `plugins/internals/agents/root-cause-analyzer.md`. It is the mandatory first response to any failure, error, warning, or anomaly (R1).

## When to Use

**MUST be invoked** when ANY of the following occurs:

- A build, test, or deploy command fails unexpectedly
- A warning or error message appears in output
- A check step fails or times out
- A validator reports an anomaly
- Documentation, a skill, or a comment diverges from observed reality
- Any unexpected behavior that cannot be immediately explained

## What It Does

The agent runs an 8-step root cause analysis process:

1. **Establish expected behavior** — what should happen
2. **Capture actual behavior** — what actually happened (with evidence)
3. **Identify the mechanism** — how the system produced the actual behavior
4. **Find the missed control** — what should have prevented it
5. **Assess blast radius** — what else is affected
6. **Determine root cause** — the fundamental issue, not a symptom
7. **Propose root fix** — a fix that prevents recurrence
8. **Document the finding** — record the RCA result

## Cross-References

- `/charly-internals:strict-policy` — R1 mandate and forbidden-rationalization rules
- `/charly-internals:agents` — agent roster and conventions
- `/charly-internals:cutover-policy` — how RCA findings feed into cutovers

## When to Use This Skill

Invoke when you need to understand the root-cause-analyzer agent's purpose, when it must be invoked, or what its 8-step process covers. The agent itself is at `plugins/internals/agents/root-cause-analyzer.md`.
