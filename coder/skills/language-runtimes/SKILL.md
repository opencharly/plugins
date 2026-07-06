---
name: language-runtimes
description: |
  Multi-language runtime meta-layer — Go, PHP, .NET 9 SDK, nodejs-devel,
  python3-devel, ramalama. System Python via RPM (not pixi-python). Uses
  nodejs and rust candies as explicit deps.
  Use when working with polyglot development or composing multiple language
  runtimes into a single box.
---

# language-runtimes -- Go, PHP, .NET, nodejs-devel, python3-devel

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs`, `rust` |
| Install files | `charly.yml` (packages only) |

## Packages (RPM)

- `dotnet-sdk-9.0` — Microsoft .NET 9 SDK (~600 MB, dominant size)
- `golang-bin` — Go compiler + standard library
- `golang-bazil-fuse-devel` — Go FUSE bindings (for candies compiling FUSE Go code)
- `libicu` — ICU i18n library (required by .NET)
- `php` — PHP CLI + core modules
- `python3-devel` — system Python 3 + dev headers
- `python3-ramalama` — RamaLama tool (Python)
- `nodejs-devel` — Node.js headers (some native-module compiles need this alongside the `nodejs` candy's runtime)

## Packages (pac) — Arch Linux

- `dotnet-sdk` — in `[extra]` (no third-party repo needed)
- `go`, `icu`, `php`, `python` — all `[core]` / `[extra]`. Arch ships headers with the main package (no `-devel` split), so `nodejs-devel` / `python3-devel` have no separate `pac:` entries.

Drops on Arch: `python3-ramalama` (not packaged — install via `uv tool install ramalama`), `golang-bazil-fuse-devel` (Go library fetched via `go get`).

## Packages (deb) — Debian + Ubuntu

- `golang-go` — Go compiler + stdlib
- `libicu-dev` — ICU with dev headers
- `php-cli` — PHP CLI binary (Debian splits `php` into `php-cli` / `php-fpm` / etc.)
- `python3-dev` — system Python 3 + dev headers

`dotnet-sdk-9.0` is **not** in the `deb:` package list. It's installed by a cross-distro `command:` plan step via Microsoft's official `dotnet-install.sh` — see the next subsection. `python3-ramalama`, `golang-bazil-fuse-devel`, `nodejs-devel` are dropped (not packaged on Debian/Ubuntu).

### dotnet-sdk-9.0 via Microsoft's `dotnet-install.sh`

Cross-distro parity for .NET 9 requires juggling three asymmetric availability windows:

| Distro | Where dotnet-sdk-9.0 lives |
|---|---|
| Fedora 43 | Distro repo (`rpm:` pulls `dotnet-sdk-9.0`) |
| Arch | `[extra]` (`pac:` pulls `dotnet-sdk`) |
| Debian 13 trixie | Microsoft's trixie apt repo has it; Debian main does not |
| Ubuntu 24.04 noble | **Neither** Canonical noble (ships 8.0 + 10.0) **nor** Microsoft's noble apt repo (ships only 10.0) has 9.0 |

Rather than carrying that asymmetry in candy code, the candy uses Microsoft's official cross-distro installer script, channel-pinned to `9.0`. It installs to `/usr/share/dotnet` and symlinks `/usr/bin/dotnet`:

```yaml
# a plan step in the language-runtimes candy's plan: list
plan:
    - run: install the .NET 9 SDK on Debian/Ubuntu via dotnet-install.sh
      command: |
          if command -v dotnet >/dev/null 2>&1; then
            exit 0                        # already installed by distro rpm/pac
          fi
          if ! command -v apt-get >/dev/null 2>&1; then
            exit 0                        # non-Debian-family + no dotnet — intentional drop
          fi
          install -d /usr/share/dotnet
          curl -fsSL https://builds.dotnet.microsoft.com/dotnet/scripts/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
          chmod +x /tmp/dotnet-install.sh
          /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/share/dotnet
          ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
          rm -f /tmp/dotnet-install.sh
      run_as: root
```

On `ghcr.io/opencharly/ubuntu-coder:latest`:

```
$ /usr/bin/dotnet --version
9.0.313
```

Idempotent: the outer `command -v dotnet` guard makes this plan step a no-op on Fedora/Arch (where the distro package already installed dotnet) and on rebuilds (where the previous run already placed the symlink). Runtime dependency: `libicu-dev` (already installed by the candy's `deb:` section).

See `/charly-image:layer` for general cross-distro plan-step authoring patterns.

## Tag-section overrides

- `debian:13:` — just packages (same as generic `deb:`).
- `ubuntu:24.04:` — just packages (same as generic `deb:`).

Both exist so future Microsoft-apt-repo-based installs can be slotted into tag sections via `repos:` + `package:` without disturbing the generic `deb:` fallback.

## No pixi-python dependency — system Python only

This candy does NOT declare `require: python`, so it pulls in neither the
`python` charly-layer nor the `pixi` charly-layer (and hence no ~500 MB conda-forge
Python env). It installs `python3-devel` + `python3-ramalama` via RPM —
**system Python** — which is all its content references. Consumers of
`language-runtimes` get only the RPM Python stack.

Consequence for `/charly-coder:fedora-coder` (the biggest consumer): the whole
`python` / `pixi` charly-layer chain stays out of the resolved candy set (because
`/charly-coder:uv` and `/charly-infrastructure:supervisord` likewise carry no python
dep). See CLAUDE.md "Key Rules" → *"Don't declare defensive deps"* for the
general rule.

If you genuinely need the pixi-python env (e.g. a candy that
installs a Python package from conda-forge via pixi), declare
`require: python` on THAT candy directly — don't rely on transitive
pulls.

## Tests

Six build-scope tests ship with the candy:

| Test | Purpose |
|---|---|
| `dotnet-binary` + `dotnet-version` | .NET SDK installed and responsive |
| `php-binary` + `php-version` | PHP CLI reachable |
| `system-python3` + `system-python3-version` | `/usr/bin/python3` is the system interpreter (the RPM-installed one; explicitly NOT a pixi-env path) |

Go and Node.js testing is delegated to the `/charly-coder:golang` and
`/charly-coder:nodejs` candy skills — those are
the single sources of truth for their respective binaries.

## Usage

```yaml
# charly.yml — compose the candy as an inline list in the box body
my-polyglot:
    candy:
        base: fedora
        candy: [language-runtimes]
```

## Used In Boxes

- `/charly-coder:fedora-coder` — kitchen-sink dev box, canonical RPM consumer.
- `/charly-coder:arch-coder` — pacman-based sibling.
- `/charly-coder:debian-coder`, `/charly-coder:ubuntu-coder` — deb-based siblings, consumers of the dotnet-install.sh plan step.

## Related Candies

- `/charly-coder:nodejs` — Node.js runtime (direct dependency)
- `/charly-coder:rust` — Rust toolchain (direct dependency)
- `/charly-languages:python` — Pixi-python env. **Not a dep of this candy.**
- `/charly-coder:golang` — Go toolchain (may be added separately for clarity even though `golang-bin` is already in this candy's RPM list)
- `/charly-coder:uv` — direct-download Rust binary (also carries no pixi-python dep)

## Related Commands

- `/charly-image:layer` — authoring reference (tag-section cascade, `command:` vs declarative repos)
- `/charly-build:build` — `base_user:` and bootstrap packages
- `/charly-core:shell` — verify runtimes inside a container

## When to Use This Skill

**MUST be invoked** when:

- Composing `language-runtimes` into a box.
- Debating pixi-python vs. system python3 — this candy is the canonical
  "system python3 only" example.
- Understanding why the `python` charly-layer is missing from a box that
  uses language-runtimes (that's by design).

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
