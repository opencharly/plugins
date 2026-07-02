---
name: hermes-playwright
description: |
  Hermes AI agent box with Playwright Chromium browser for web automation.
  Builds on top of the headless hermes box, adding Chromium and system deps.
  MUST be invoked before building, deploying, configuring, or troubleshooting the hermes-playwright box.
---

# hermes-playwright

Hermes AI agent with Playwright Chromium — web scraping, browser automation, and all headless agent capabilities.

## Box Properties

| Property | Value |
|----------|-------|
| Base | fedora |
| Candies | agent-forwarding, hermes, hermes-playwright, dbus, charly |
| Platforms | linux/amd64 |
| Security | shm_size: 1g |
| Registry | ghcr.io/opencharly |

## Full Candy Stack

Builds on the base `hermes` candy (not the hermes box), adding Playwright Chromium:

1. `fedora` base + `agent-forwarding` + `hermes` + `hermes-playwright` + `dbus` + `charly`
2. `hermes-playwright` -- Playwright npm package + Chromium Headless Shell + system deps

## Quick Start

```bash
charly box build hermes-playwright
charly config hermes-playwright -e OLLAMA_API_KEY=your-key   # or OPENROUTER_API_KEY
charly start hermes-playwright
```

The hermes entrypoint performs single-phase, first-start-only auto-configuration of LLM providers and MCP servers from env vars. See `/charly-hermes:hermes` for full provider configuration and MCP auto-discovery details.

## Playwright Usage

### From Node.js
```bash
charly shell hermes-playwright -c "NODE_PATH=~/.npm-global/lib/node_modules node -e \"
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage();
  await page.goto('https://example.com');
  console.log(await page.title());
  await browser.close();
})();
\""
```

### Via npx CLI
```bash
charly shell hermes-playwright -c "npx playwright --version"
```

## Key Candies

- `/charly-hermes:hermes` -- core agent (inherited)
- `/charly-hermes:hermes-playwright` -- Playwright + Chromium + system deps

## Fedora Compatibility Note

Playwright's `--with-deps` flag does not support Fedora (falls back to Ubuntu's `apt-get`). The `hermes-playwright` candy works around this by:
1. Installing Chromium's system library dependencies via rpm packages in `charly.yml`
2. Installing only the browser binary via `npx playwright install chromium` in `task:`

The `PLAYWRIGHT_BROWSERS_PATH=/tmp/.cache/ms-playwright` env var is set automatically.

## Related Boxes

- `/charly-hermes:hermes` -- full-featured standalone hermes (no browser, uses cross-container CDP)

## Verification

After `charly start`:
```bash
charly status hermes-playwright               # container running
charly service status hermes-playwright        # all services RUNNING
charly shell hermes-playwright -c "hermes --version"
charly shell hermes-playwright -c "npx playwright --version"
# Full browser launch test:
charly shell hermes-playwright -c "NODE_PATH=~/.npm-global/lib/node_modules node -e \"
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({ headless: true });
  const p = await b.newPage();
  await p.goto('https://example.com');
  console.log('Title:', await p.title());
  await b.close();
  console.log('OK');
})();
\""
```

## When to Use This Skill

**MUST be invoked** when the task involves the hermes-playwright box, Hermes Agent with browser automation, or deploying hermes with Playwright. Invoke this skill BEFORE reading source code or launching Explore agents.

## Related

- `/charly-image:image` — image family umbrella (`candy:` image entries — those carrying `base:`/`from:` — in `charly.yml`, build/validate/inspect/list)
- `/charly-build:build` — the embedded build vocabulary (distros, builders, init-systems)
