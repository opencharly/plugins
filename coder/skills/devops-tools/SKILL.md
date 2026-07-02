---
name: devops-tools
description: |
  DevOps CLI tools: AWS CLI, Scaleway, kubectx/kubens, OpenTofu, wrangler, bind-utils, jq, rsync.
  Use when working with cloud infrastructure, DNS lookups, infrastructure-as-code, or DevOps tooling.
---

# devops-tools -- cloud and infrastructure CLI tools

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `nodejs` |
| Install files | `task:`, `package.json` |

## Packages

- `bind-utils` (RPM) -- DNS lookup tools (dig, nslookup)
- `jq` (RPM) -- JSON processor
- `rsync` (RPM) -- file synchronization
- `wrangler` (npm) -- Cloudflare Workers CLI

## Cross-distro coverage

`rpm:` (Fedora) · `pac:` (Arch) · `deb:` (Debian/Ubuntu — `dnsutils` replaces `bind-utils`, `jq`, `rsync` identical). The cloud-CLI tools (AWS, Scaleway, kubectx/kubens, OpenTofu) are curl-downloaded binaries — distro-agnostic by construction, no per-package-manager work needed.

## Usage

```yaml
# charly.yml
my-image:
  candy:
    - devops-tools
```

## Used In Boxes

- (none currently enabled)

## Related Candies

- `/charly-coder:nodejs` -- Node.js dependency for npm packages

## When to Use This Skill

Use when the user asks about:

- AWS CLI, Scaleway CLI, or cloud provider tools
- kubectx or kubens for Kubernetes context switching
- OpenTofu or infrastructure-as-code
- Cloudflare Wrangler
- DNS tools (dig, nslookup) or jq/rsync in containers

## Author + Test References

- `/charly-image:layer` — candy authoring reference (tasks, vars, env_provide, tests block syntax)
- `/charly-check:check` — declarative testing framework for the `check:` block
