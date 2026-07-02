---
name: vscode
description: |
  Visual Studio Code editor installed from Microsoft's RPM repository.
  Use when working with VS Code installation or configuration in container images.
---

# vscode -- Visual Studio Code editor

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` |

## Packages

- `code` (RPM, from Microsoft repo) -- Visual Studio Code

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - vscode
```

## Used In Boxes

- (none currently enabled)

## Related Candies
- `/charly-coder:dev-tools` — CLI dev tools companion
- `/charly-coder:typst` — document tooling sibling

## Related Commands
- `/charly-core:shell` — launch vscode inside the container
- `/charly-build:build` — rebuild after candy changes

## When to Use This Skill

Use when the user asks about:

- VS Code installation in containers
- Microsoft code editor setup
- The `code` RPM package or Microsoft repository

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, task verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
