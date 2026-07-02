---
name: docker-ce
description: |
  Docker CE engine with buildx and compose plugins from the official Docker repository.
  Use when working with Docker, container builds, or Docker Compose.
---

# docker-ce -- Docker CE engine and plugins

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `task:` |

## Packages

RPM (from `docker-ce-stable` repo): `containerd.io`, `docker-buildx-plugin`, `docker-ce`, `docker-ce-cli`, `docker-compose-plugin`

## Cross-distro coverage

`rpm:` (Fedora — Docker's yum repo), `pac:` (Arch — `docker` metapackage from `extra`), `deb:` — via distro-version tag sections `debian:13:` and `ubuntu:24.04:` because the upstream apt repo URL differs per distro codename (`https://download.docker.com/linux/debian trixie` vs `.../ubuntu noble`). Each tag section declares its own `repos:` block with the correct URL + GPG key; packages (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`) are identical. See `/charly-image:layer` "distro-version tag sections".

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - docker-ce
```

## Used In Boxes

- (none currently enabled)

## Related Candies
- `/charly-distros:container-nesting` — Alternative podman-based nested container support
- `/charly-coder:kubernetes-layer` — Sibling kubectl/Helm commonly paired with docker-ce
- `/charly-coder:github-actions` — Sibling candy needing a container engine for act runs

## Related Commands
- `/charly-build:build` — Build the bootc image including docker-ce packages
- `/charly-vm:vm` — Run the bootc image as a VM to test the docker engine

## When to Use This Skill

Use when the user asks about:

- Docker CE inside containers
- Docker buildx or compose plugins
- The `docker-ce` candy or Docker repository setup

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
