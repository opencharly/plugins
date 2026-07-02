---
name: fedora-test
description: |
  Test box with Traefik reverse proxy and testapi service.
  Currently disabled. Used for development testing.
  MUST be invoked before building or troubleshooting the fedora-test box.
---

# fedora-test

Development test box with Traefik reverse proxy and a FastAPI test service.

Lives in the **`opencharly/distro-fedora`** repo (git submodule at **`box/fedora`**).
Its `fedora` base is bare-local in the same self-contained submodule
(`import: []`) — `base: fedora`; the
`agent-forwarding`/`traefik`/`testapi` candies are pulled by github reference.
Build from the submodule: `charly -C box/fedora box build fedora-test`.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Layers | agent-forwarding, traefik, testapi |
| Platforms | linux/amd64, linux/arm64 |
| Ports | 8000 (Traefik HTTP), 8080 (Traefik dashboard) |
| Status | enabled |

## Purpose

Used for testing Traefik routing, service health checks, and the `testapi` candy. The testapi service runs on port 9090 and is routed via `testapi.localhost` through Traefik.

## Key Candies

- `/charly-infrastructure:traefik` — Reverse proxy
- `/charly-infrastructure:testapi` — FastAPI test service

## Related Boxes
- `/charly-distros:fedora` — parent base image
- `/charly-distros:valkey-test` — sibling test box (disabled)

## Related Commands
- `/charly-build:build` — build the fedora-test box
- `/charly-build:validate` — validate the test candy composition

## When to Use This Skill

**MUST be invoked** when the task involves the fedora-test box or Traefik routing validation.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
