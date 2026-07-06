---
name: gh
description: |
  GitHub CLI, git, and git-lfs — the single-responsibility home for all
  git/GitHub tooling. Ships the noscripts + post-install dance for git-lfs
  so the RPM's systemd trigger doesn't fail at build time.
  Use when composing git + gh + git-lfs into a box, or when deciding
  which candy should own a git-related binary.
---

# gh -- GitHub CLI + git + git-lfs

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (packages + one post-install `run:` step) |
| Depends | **(none)** |

## Packages

- RPM (with `--setopt=tsflags=noscripts`): `gh`, `git`, `git-lfs`
- pac: `github-cli`, `git`, `git-lfs`

## Why `tsflags=noscripts` + a post-install `run:` step

The `git-lfs` RPM's `%post` scriptlet runs `git-lfs install --system`
which tries to modify `/etc/` and talk to systemd — operations that
fail (loudly or silently) inside a buildah container. We install with
noscripts and then run the git-lfs hook configuration manually:

```yaml
# a plan step in the gh candy's plan: list
plan:
    - run: configure git-lfs system hooks
      command: /usr/bin/git-lfs install --system --skip-repo 2>/dev/null || true
      run_as: root
```

The `|| true` tolerates distros/versions where the command layout
differs; `--skip-repo` prevents git-lfs from trying to touch a repo
that doesn't exist in the build container.

## Single-responsibility ownership

This candy is the exclusive home for `gh`, `git`, and `git-lfs` — no other
candy (including `/charly-coder:dev-tools`) installs them. That keeps ownership
unambiguous ("which candy do I look at to update the git-lfs version?" — this
one) and avoids duplicate test ids (`gh-binary` collisions).

Effect for candy authors: any box that wants git tooling composes `gh`
explicitly. The four power-user boxes (`charly-arch`, `charly-fedora`,
`fedora-coder`, `githubrunner` via the `charly` chain) all list `gh`
explicitly.

## Tests

Six build-scope tests:

| Test | Purpose |
|---|---|
| `gh-binary` | `/usr/bin/gh` exists |
| `gh-version` | `gh --version` exits 0 |
| `git-binary` | `/usr/bin/git` exists |
| `git-version` | `git --version` exits 0 |
| `git-lfs-binary` | `/usr/bin/git-lfs` exists |
| `git-lfs-version` | `git-lfs --version` exits 0 |

## Cross-distro coverage

`rpm:` (Fedora — from the `github-cli` COPR / community repo), `pac:` (Arch — `github-cli` from `extra`), `deb:` (Debian/Ubuntu — adds `https://cli.github.com/packages` as an apt repo with signed-by key; ships `gh`, `git`, `git-lfs`). Full parity across all three package families.

## Usage

```yaml
# box charly.yml — compose the candy as an inline list in the box body
my-box:
    candy:
        base: fedora
        candy: [gh]
```

## Used In Boxes

- `/charly-coder:charly-arch`, `/charly-distros:charly-fedora`, `/charly-coder:fedora-coder` — power-user boxes that compose gh explicitly
- `/charly-openclaw:openclaw-desktop` — streaming-desktop sibling
- Any box composing `hermes-full`

## Related Candies

- `/charly-coder:dev-tools` — does not install git/gh/git-lfs (this candy owns them)
- `/charly-distros:agent-forwarding` — pairs with gh for SSH/GPG agent access (you usually want both when driving gh from inside a container with the host's GPG keys forwarded)
- `/charly-distros:github-runner` — self-hosted Actions runner; different candy, different purpose
- `/charly-coder:github-actions` — installs `act` + `actionlint` for local Actions testing; also different from this candy

## Related Commands

- `/charly-build:secrets` — provision `GITHUB_TOKEN` for `gh auth login`
- `/charly-core:shell` — run gh interactively inside a container

## When to Use This Skill

**MUST be invoked** when:

- Adding git or GitHub CLI access to a box (compose this candy —
  DO NOT add `gh`, `git`, or `git-lfs` to any other candy's packages).
- Debugging why `git-lfs install` fails at build time (the noscripts +
  post-install pattern here is the fix).
- Understanding why `/charly-coder:dev-tools` does not install gh
  (this candy holds single-responsibility ownership of git tooling).

## Related

- `/charly-image:layer` — candy authoring reference (`charly.yml` schema, plan-step verbs, service declarations)
- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
