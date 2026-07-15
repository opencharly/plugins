---
name: workspace-mount
description: |
  Mounts a virtiofs share tagged `workspace` at /workspace inside a VM guest via
  a systemd .mount unit. Use when a kind:vm entity shares a host directory into
  the guest and you need it auto-mounted (and re-mounted at every boot).
---

# workspace-mount — virtiofs /workspace mount

A guest-side candy that mounts the virtiofs share tagged `workspace` at
`/workspace` and enables it so it re-mounts on every boot — load-bearing for an
**autostarting** VM that must come back with its share already mounted.

## What it does

- `mkdir /workspace`
- writes `/etc/systemd/system/workspace.mount` (`What=workspace`, `Where=/workspace`,
  `Type=virtiofs`, `WantedBy=multi-user.target`)
- `systemctl daemon-reload` + `enable` (boot) + `start` (now, tolerant) — the
  start is `|| true` so an image-build chroot with no device / no systemd does
  not fail the candy; the enabled unit mounts at the next boot.

## The contract

The mount **tag `workspace`** is the contract between the host-side share and
this candy. The `kind: vm` entity must declare a matching virtiofs filesystem:

```yaml
libvirt:
  devices:
    filesystems:
      - {driver: virtiofs, accessmode: passthrough, source: /home/me, target: workspace}
```

`target: workspace` (the entity) ↔ `What=workspace` (this candy). The shared
memory backing virtiofs requires is auto-paired by the renderer (see
`/charly-internals:libvirt-renderer`), so the entity declares only the filesystem.

## Check

- `workspace-mount-unit` — the `.mount` unit file contains `Type=virtiofs`.
- `workspace-virtiofs-rw` — skip-aware: N/A when no share is attached (image
  build / no-device target); when `/workspace` IS mounted it MUST be `virtiofs`
  and writable. Mirrors the GPU check gate's skip-with-explanation pattern.

## Used in

The `cachyos-coder` operator workstation VM (`box/cachyos`), mounting the
operator's `/home/<user>` → `/workspace`. Generic for any pod-in-VM share.

## Related

- `/charly-internals:libvirt-renderer` — `mapFilesystem` + `ensureVirtiofsSharedMemory`
- `/charly-vm:vms-catalog` — `filesystems:` authoring on the kind:vm entity
- `/charly-vm:cachyos-bootstrap-vm` — the CachyOS VM family that consumes it
- `/charly-image:layer` — candy authoring reference

## When to Use This Skill

Use when authoring or debugging a virtiofs host-directory share mounted into a VM
guest, or the `workspace-mount` candy specifically.
