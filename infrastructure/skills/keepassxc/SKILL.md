---
name: keepassxc
description: |
  KeePassXC password manager desktop app.
  Single-responsibility candy (rpm+pac, one test).
  Use when adding KeePassXC to a box as a standalone candy.
---

# keepassxc -- KeePassXC password manager

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | none |
| Ports | none |
| Service | none (on-demand GUI) |
| Install files | `task:` only |

## Packages

- Fedora / RHEL (`rpm:`): `keepassxc`
- Arch Linux (`pac:`): `keepassxc`

Single package, no custom repos. Ships the KeePassXC GUI binary at `/usr/bin/keepassxc`.

## Usage

```yaml
# charly.yml
my-desktop-image:
  candy:
    - selkies-desktop      # or another desktop base
    - keepassxc            # this layer
```

## Used In Boxes

- (none currently)

## Tests

One declarative check (build-scope):

- `keepassxc-binary` — `/usr/bin/keepassxc` executable exists

No deploy-scope tests: KeePassXC is a GUI app launched on-demand by the user inside the desktop session — there's no listening port or headless responder to probe.

## Relationship to `/charly-build:secrets`

This candy is the **GUI** for editing `.kdbx` databases. `/charly-build:secrets` is the charly CLI credential store — which talks to the **Secret Service** (system keyring), NOT to a `.kdbx` file directly.

- Author a `.kdbx` file in KeePassXC (GUI) → enable its **FdoSecrets** plugin (Settings → Secret Service Integration) and mark the group "Secret Service exposed" → its entries appear on the Secret Service bus, where `charly`'s keyring backend reads them. No `charly`-side `.kdbx` configuration is involved.
- See `/charly-infrastructure:keepassxc-keyring` for the candy that wires KeePassXC as the host's Secret Service provider.

## Related Skills

- `/charly-build:secrets` — charly CLI credential store (Secret Service + GPG; reads a KeePassXC database only via its FdoSecrets / Secret Service exposure)
- `/charly-image:layer` — candy authoring reference
- `/charly-check:check` — declarative testing reference

## When to Use This Skill

Use when the user asks about:

- Adding KeePassXC to a container or VM box as a standalone candy
- Relationship between the KeePassXC GUI and `charly secrets`
