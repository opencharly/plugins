---
name: cloud-init
description: |
  Cloud-init for instance initialization in cloud/VM environments with NoCloud datasource.
  Use when working with cloud-init, VM provisioning, or cloud instance bootstrapping.
---

# cloud-init -- cloud instance initialization

## Candy Properties

| Property | Value |
|----------|-------|
| Dependencies | `sshd` |
| Install files | `run:` steps, `charly.yml` |

## Packages

- `cloud-init` (RPM) -- cloud instance initialization
- `cloud-utils-growpart` (RPM) -- partition growing utility

## Usage

```yaml
# charly.yml
my-cloud-image:
  candy:
    base: "quay.io/fedora/fedora-bootc:43"
    bootc: true
    candy: [cloud-init]
```

## Used In Boxes

Used in bootc images for VM/cloud deployments. Depends on `sshd`.

## Host-side pairing with `kind: vm` entities

This candy installs the **guest-side** cloud-init package — the daemon that reads a NoCloud seed ISO at first boot. The **host-side** companion is the `RenderCloudInit` path in the `charly` binary itself (`/charly-internals:cloud-init-renderer`), which produces that seed ISO from the structured `VmSpec.CloudInit` block on a `kind: vm` entity.

The two sides cooperate across the host/guest boundary:

- `/charly-internals:cloud-init-renderer` emits `user-data` + `meta-data` + `network-config` + seeds ISO via xorriso.
- This guest-side candy installs cloud-init so the guest reads `/dev/sr0` (the seed ISO) at boot.
- The `composeUsers` adopt-merge pattern (renderer-side) deposits the SSH pubkey in `~<base_user>/.ssh/authorized_keys` without `useradd`.

For cloud_image VMs (`source.kind: cloud_image`), cloud-init typically comes pre-installed in the upstream qcow2 — this candy isn't needed; author the VM entity directly in `vm.yml`. For bootc VMs that want cloud-init provisioning, add this candy explicitly. See `/charly-vm:vms-catalog` for the authoring guide and `/charly-vm:arch` for a worked example.

## Related Skills

- `/charly-coder:sshd` -- SSH server dependency
- `/charly-distros:qemu-guest-agent` — host-guest communication (paired with cloud-init in VMs)
- `/charly-vm:vm` — VM lifecycle (create, start, stop, ssh) for kind:vm entities
- `/charly-vm:vms-catalog` — kind:vm authoring reference
- `/charly-internals:cloud-init-renderer` — host-side renderer producing the NoCloud seed ISO this candy reads
- `/charly-image:layer` — candy authoring reference

## When to Use This Skill

Use when the user asks about:

- Cloud-init configuration or NoCloud datasource
- VM instance provisioning
- Cloud instance bootstrapping
- Partition growing with growpart
- System services: cloud-init-local, cloud-init, cloud-config, cloud-final

## Related

- `/charly-check:check` — declarative testing (`check:` block, `charly check box`, `charly check live`)
