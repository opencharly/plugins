---
name: k3s
description: |
  k3s binary installer (common base for k3s-server and k3s-agent).
  Use when building images that need the k3s binary but do NOT want a server/agent service started automatically.
---

# k3s -- k3s binary installer (base layer)

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml` (binary fetch + symlinks via a `run:` plan step) |
| Pinned version | `v1.31.11+k3s1` (edit `K3S_VERSION` in `charly.yml` vars to cut over) |

## What this candy does

Downloads the verified-checksum k3s binary (plus sha256sum from the
release manifest), installs it to `/usr/local/bin/k3s`, and creates
symlinks for `kubectl`, `crictl`, `ctr` (k3s is multi-call). Installs
runtime dependencies (`iptables`, `conntrack`, `socat`, `ethtool`,
`ca-certificates`) via the distro package manager — **not** via the
upstream `curl | sh` installer. Deliberate, per R9.

**No service is started by this candy.** Role selection happens in the
dependent candies `/charly-infrastructure:k3s-server` and `/charly-infrastructure:k3s-agent`,
which emit systemd units that wrap this binary with the right CLI verb
(`k3s server` vs `k3s agent`).

## Usage

Typically not used directly — compose `/charly-infrastructure:k3s-server` or
`/charly-infrastructure:k3s-agent` (both depend on this candy).

```yaml
# For a bare binary-only image (rare) — a box composes the candy via an
# inline candy: list in its body:
k3s-base:
  candy:
    base: fedora
    candy:
      - k3s
```

## Cross-distro coverage

- `rpm:` (Fedora) — `conntrack-tools`, `iptables`, `ethtool`, `socat`, `ca-certificates`
- `pac:` (Arch) — `conntrack-tools`, `iptables-nft`, `ethtool`, `socat`, `ca-certificates`
- `deb:` (Debian/Ubuntu) — `conntrack`, `iptables`, `ethtool`, `socat`, `ca-certificates`

## Tests

- `k3s --version` matches pinned version.
- `/usr/local/bin/k3s` is mode 0755.
- `/usr/local/bin/kubectl` exists as a symlink.
- Each runtime package is installed (per-distro `package_map` handles Debian's `conntrack` rename).

## Related Candies
- `/charly-infrastructure:k3s-server` — Control-plane node (depends on this candy)
- `/charly-infrastructure:k3s-agent` — Worker node (depends on this candy)
- `/charly-coder:kubernetes-layer` — Distro `kubectl`/`helm` binaries for the operator, not the cluster
