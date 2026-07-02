---
name: github-actions
description: |
  GitHub Actions local runner (act-cli) and guestfs-tools via COPR.
  Use when working with GitHub Actions, local CI testing, or act.
---

# github-actions -- Act CLI for local GitHub Actions

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `task:` |

## Packages

RPM (from COPR `goncalossilva/act`): `act-cli`, `guestfs-tools`

## Cross-distro coverage

`rpm:` (Fedora), `pac:` (Arch). `deb:` (Debian/Ubuntu) — `act` and `actionlint` are curl-downloaded GitHub release binaries (distro-agnostic already); `guestfs-tools` is dropped from deb (not in Debian main). The candy's `task:` are format-agnostic so the per-distro divergence is minimal.

## Usage

```yaml
# charly.yml
my-ci:
  candy:
    - github-actions
```

## Used In Boxes

- (none currently enabled)

## Related Candies
- `/charly-distros:github-runner` — distinct self-hosted runner candy (not act)
- `/charly-coder:docker-ce` — common companion for act workflow execution
- `/charly-coder:dev-tools` — typically paired in CI boxes

## Related Commands
- `/charly-build:build` — installs act-cli from COPR during image build
- `/charly-core:shell` — run `act` interactively to test workflows locally

## When to Use This Skill

Use when the user asks about:

- Running GitHub Actions locally
- The act CLI tool
- The `github-actions` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
