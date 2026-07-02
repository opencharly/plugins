---
name: valkey-test
description: |
  Test box with Valkey (Redis-compatible) key-value store.
  Currently disabled. Used for development testing.
  MUST be invoked before building or troubleshooting the valkey-test box.
---

# valkey-test

Development test box with Valkey in-memory data store.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Layers | agent-forwarding, supervisord, valkey |
| Platforms | linux/amd64, linux/arm64 |
| Ports | 6379 (Valkey) |
| Status | **disabled** (set `enabled: true` in charly.yml) |

## Purpose

Used for testing the Valkey candy (Redis-compatible fork). Runs as a supervisord service on port 6379.

## Key Candies

- `/charly-infrastructure:valkey` — Valkey data store
- `/charly-infrastructure:supervisord` — Process manager

## Related Boxes
- `/charly-distros:fedora` — parent base image
- `/charly-distros:fedora-test` — sibling test box

## Related Commands
- `/charly-build:build` — build the valkey-test box
- `/charly-core:service` — manage the supervised valkey service

## When to Use This Skill

**MUST be invoked** when the task involves the valkey-test box or Valkey service testing.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
