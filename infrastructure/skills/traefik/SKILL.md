---
name: traefik
description: |
  Traefik reverse proxy on ports 8000/8080/443 with automatic TLS and dynamic routing.
  Use when working with Traefik, reverse proxy, TLS certificates, or service routing.
---

# traefik -- Reverse proxy with dynamic routing

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `supervisord` |
| Ports | 8000, 8080, 443 |
| Volumes | `certs` -> `~/.traefik/acme` |
| Service | `traefik` (supervisord) |
| Install files | `task:`, `traefik.yml` |

## Usage

```yaml
# charly.yml
fedora-test:
  candy:
    - traefik
```

## Used In Boxes

- `/charly-distros:fedora-test`

## Related Candies

- `/charly-infrastructure:supervisord` -- process manager dependency
- `/charly-infrastructure:testapi` -- test service with Traefik route

## Related Commands

- `/charly-build:list` — `charly box list routes` shows Traefik route configuration

## When to Use This Skill

Use when the user asks about:

- Traefik reverse proxy setup
- Dynamic routing configuration
- TLS certificate management (ACME)
- Ports 8000, 8080, or 443
- Service routing via `*.localhost`

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
