---
name: hermes-playwright-layer
description: |
  Playwright Chromium browser for Hermes Agent with Fedora-compatible system deps.
  MUST be invoked before any work involving: Playwright in hermes containers,
  Chromium browser automation for hermes, or hermes-playwright candy configuration.
---

# hermes-playwright -- Playwright Chromium for Hermes

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `hermes` |
| Security | `shm_size: 1g` |
| Install files | `charly.yml`, `package.json`, `task:` |
| RPM packages | `alsa-lib`, `at-spi2-core`, `cups-libs`, `gtk3`, `libdrm`, `libxkbcommon`, `nss`, `mesa-dri-drivers`, `vulkan-loader`, `libXcomposite`, `libXdamage`, `libXrandr`, `pango`, `cairo` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `PLAYWRIGHT_BROWSERS_PATH` | `/tmp/.cache/ms-playwright` |

## Architecture

This is a **Tier 1 candy** (no pixi.toml) that adds Playwright + Chromium on top of the hermes candy.

### Fedora Compatibility

Playwright's `npx playwright install --with-deps` does **not support Fedora** -- it falls back to Ubuntu and tries `apt-get`, which fails. The workaround:

1. **rpm packages** in `charly.yml` install all Chromium system library dependencies manually
2. A root-phase `cmd:` task runs `npx playwright install chromium` (without `--with-deps`) to download only the browser binary

### Browser Location

Browsers are installed to `/tmp/.cache/ms-playwright/` during the build (the cmd runs as root with `HOME=/tmp`). The `PLAYWRIGHT_BROWSERS_PATH` env var ensures Playwright finds them at runtime.

### Using Playwright from Node.js

The Playwright npm package is installed **globally** via the npm builder (from `package.json`). To `require('playwright')` in Node.js, set `NODE_PATH`:

```bash
NODE_PATH=~/.npm-global/lib/node_modules node -e "const { chromium } = require('playwright'); ..."
```

Or use the `npx` CLI directly:
```bash
npx playwright --version
```

## Usage

```yaml
# charly.yml
hermes-playwright:
  base: fedora
  candy:
    - agent-forwarding
    - hermes
    - hermes-playwright
    - dbus
    - charly
```

## Used In Boxes

- `/charly-hermes:hermes-playwright` -- hermes with Playwright Chromium

## Related Candies

- `/charly-hermes:hermes` -- base hermes agent (required dependency)
- `/charly-selkies:chrome` -- similar pattern for Chrome system deps
- `/charly-hermes:playwright-layer` -- OpenClaw's Playwright layer (npm only, no Chromium binary)

## When to Use This Skill

**MUST be invoked** when the task involves Playwright browser automation in hermes containers, Chromium system dependencies on Fedora, or the hermes-playwright candy. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
