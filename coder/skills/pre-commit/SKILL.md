---
name: pre-commit
description: |
  Pre-commit git hooks framework via pixi, plus markdownlint-cli via npm.
  Use when working with git hooks, linting, or code quality tooling.
---

# pre-commit -- Git hooks framework

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs` |
| Install files | `charly.yml`, `pixi.toml`, `package.json`, `task:` |

## Packages

Pixi (conda-forge): `pre-commit`
npm: `markdownlint-cli`

## Usage

```yaml
# charly.yml
my-dev:
  candy:
    - pre-commit
```

## Used In Boxes

- No enabled boxes use this candy directly (dev tool layer)

## Related Candies

- `/charly-coder:nodejs` -- required dependency (provides npm for markdownlint-cli)
- `/charly-languages:pixi` -- transitive (provides pixi for pre-commit installation)

## When to Use This Skill

Use when the user asks about:

- Pre-commit hooks in containers
- Git hook frameworks
- Markdown linting
- The `pre-commit` candy

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, env_provide, tests block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block
