---
name: pixi
description: |
  Pixi package manager binary with environment and PATH setup.
  Use when working with pixi, conda-forge packages, or Python environment management.
---

# pixi -- Pixi package manager

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `task:` |

## Environment Variables

| Variable | Value |
|----------|-------|
| `PIXI_CACHE_DIR` | `~/.cache/pixi` |
| `RATTLER_CACHE_DIR` | `~/.cache/rattler` |

PATH additions: `~/.pixi/bin`, `~/.pixi/envs/default/bin`

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - pixi
```

## Used In Boxes

- `/charly-distros:fedora-builder` (direct)
- `/charly-distros:arch-builder` (direct)
- Transitive dependency via `python` / `supervisord` in most service boxes

## Related Candies

- `/charly-languages:python` -- depends on pixi for Python 3.13 installation
- `/charly-coder:pre-commit` -- uses pixi for pre-commit installation

## Pinned pixi version (`var: PIXI_VERSION`)

The `pixi` candy installs a **pinned** pixi release — `var: PIXI_VERSION` drives the
`releases/download/${PIXI_VERSION}/pixi-${BUILD_ARCH}-unknown-linux-musl.tar.gz`
download. Bump `PIXI_VERSION` (and the candy `version:`) deliberately to adopt a
newer pixi; do NOT revert to an unpinned `releases/latest` URL, which makes the
same candy version install a different pixi over time (non-reproducible builds,
against charly's content-hash/CalVer model). Candy `pixi.toml` files use the
modern `[workspace]` table (the deprecated `[project]` form emits a warning under
pixi ≥ 0.70 and is being removed upstream).

## Committed `pixi.lock` → `pixi install --frozen`

Every pixi candy ships a committed `pixi.lock` next to its `pixi.toml`. When a
lock is present, generation auto-flips the build stage from `pixi install` (a
full SAT solve over the conda + PyPI indexes on every cache miss) to
`pixi install --frozen` (install straight from the lock — no solve,
deterministic, better cache reuse). The flip is automatic via `HasPixiLock`
detection (`charly/layers.go`) → the `pixi.toml+lock` install command in
the embedded build vocabulary (`charly/charly.yml`); no per-candy config.

**Regenerate the lock whenever you change `pixi.toml`** — `--frozen` fails the
build loudly if the lock is stale (no silent skew). Generate with the builder's
own pixi so the lock format matches what installs it, e.g.:

```bash
charly shell fedora-builder --tag <calver> --bind workspace="$PWD/candy/<name>" \
  -c 'grep -q system-requirements pixi.toml || printf "\n[system-requirements]\nlibc = { family = \"glibc\", version = \"2.39\" }\n" >> pixi.toml; pixi lock'
```

The `[system-requirements]` glibc fix mirrors what the build stage injects, so
the committed lock resolves the same manylinux wheels the build installs.

## When to Use This Skill

Use when the user asks about:

- Pixi package manager setup
- Conda-forge package installation
- Python environment base candy
- The `pixi` candy or `PIXI_CACHE_DIR`

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
