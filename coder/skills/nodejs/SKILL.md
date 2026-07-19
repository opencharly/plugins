---
name: nodejs
description: |
  Node.js and npm via system packages (RPM/DEB) with global npm prefix.
  Use when working with Node.js, npm, or JavaScript/TypeScript tooling.
---

# nodejs -- Node.js and npm runtime

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `NPM_CONFIG_PREFIX` | `~/.npm-global` |
| `npm_config_cache` | `~/.cache/npm` |

PATH additions: `~/.npm-global/bin`

## Packages

RPM: `nodejs`, `npm`
DEB: `nodejs`, `npm`
PAC: `nodejs`, `npm`

## pnpm (standalone binary)

The candy installs the **pnpm** standalone binary (self-contained — it bundles
its own node) to `/usr/local/bin/pnpm` via a `task:` download. It is deliberately
NOT a `package.json` dependency: a `package.json` would trigger the npm
multi-stage builder on this candy, and the builder images that COMPOSE nodejs
(`arch-builder` / `fedora-builder`) cannot self-provide the npm builder. The
binary on `/usr/local/bin` is on the default system PATH for every user (incl.
root — Immich runs its pnpm build as root). Immich and other pnpm consumers use
this pnpm to drive their build.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - nodejs
```

## Used In Boxes

- `/charly-distros:fedora-builder`
- `/charly-distros:arch-builder`
- Transitive dependency for `openclaw`, `pre-commit`, and other candies

## Related Candies

- `/charly-coder:pre-commit` -- depends on nodejs
- `/charly-immich:immich-layer` -- uses the candy's pnpm to build Immich

## When to Use This Skill

Use when the user asks about:

- Node.js or npm setup in containers
- Global npm package installation
- The `nodejs` candy or npm configuration

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
