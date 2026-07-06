---
name: himalaya
description: |
  Himalaya email CLI (IMAP/SMTP).
  Use when working with the himalaya candy.
---

# himalaya -- Email CLI

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (`run:` step) |
| Depends | `rust` |

## Usage

```yaml
# box charly.yml — compose the candy as an inline list in the box body
my-box:
  candy:
    base: fedora
    candy: [himalaya]
```

## Used In Boxes

- `openclaw-full` (via `openclaw-full` metalayer)

## Related Candies
- `/charly-coder:rust` — required Rust toolchain dependency
- `/charly-openclaw:openclaw-full` — metalayer that includes himalaya
- `/charly-infrastructure:gnupg` — pairs with himalaya for PGP-encrypted email

## Related Commands
- `/charly-build:secrets` — provision IMAP/SMTP credentials for himalaya
- `/charly-core:shell` — run himalaya interactively inside a container
- `/charly-build:build` — compiles himalaya via the Cargo builder during image build

## When to Use This Skill

Use when the user asks about:
- Email CLI access (IMAP/SMTP)
- Himalaya email client in containers
- The `himalaya` candy

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
