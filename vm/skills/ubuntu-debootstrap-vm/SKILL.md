---
name: ubuntu-debootstrap-vm
description: |
  Ubuntu bootstrap VM (kind:vm ubuntu-debootstrap) — source.kind: bootstrap via
  ubuntu-debootstrap-builder + debootstrap, ext4 rootfs, uefi-insecure. Plus the
  disposable check-ubuntu-debootstrap-vm deploy. Lives in the opencharly/distro-ubuntu submodule.
  MUST be invoked before editing ubuntu-debootstrap or its check bed.
---

# ubuntu (VM)

`source.kind: bootstrap` VM that builds an Ubuntu 24.04 rootfs from scratch via
`debootstrap` (using `/charly-distros:ubuntu-debootstrap-builder`), then boots it
under libvirt/QEMU.

The `ubuntu-debootstrap` VM entity and its `check-ubuntu-debootstrap-vm` disposable
test bed live in the **`opencharly/distro-ubuntu`** repo (git submodule at
**`box/ubuntu`**), all in that repo's unified `charly.yml`. The bed is a
`disposable: true` deploy (a check bed is just a deploy carrying `disposable: true`
— there is no separate bed kind), driven by `charly check run
check-ubuntu-debootstrap-vm`. Drive the VM lifecycle from the submodule:
`charly -C box/ubuntu vm build ubuntu-debootstrap` +
`charly -C box/ubuntu vm create ubuntu-debootstrap` (or
`charly --repo opencharly/distro-ubuntu …`).

## VM Configuration (from box/ubuntu/charly.yml)

| Setting | Value |
|---|---|
| Source | `kind: bootstrap`, `builder: debootstrap`, `builder_image: ubuntu-debootstrap-builder` |
| Distro | ubuntu |
| rootfs | ext4 |
| Disk / RAM / CPU | 20G / 4G / 2 |
| Machine / firmware | q35 / uefi-insecure |
| Network | user mode |
| SSH | user `ubuntu`, port 12229, key_source generate |

The `ubuntu` distro config (`inherits: debian`; debootstrap suite `noble`,
mirror, base packages) comes from the embedded build vocabulary
(`charly/charly.yml`, baked into the charly binary), available to every repo
without an import. The embedded vocabulary carries BOTH distro configs, so
`inherits: debian` resolves without referencing `opencharly/distro-debian`.

## Check bed

`check-ubuntu-debootstrap-vm` is a `disposable: true` deploy
(`vm: {from: ubuntu-debootstrap, disposable: true}`), so
`charly -C box/ubuntu check run check-ubuntu-debootstrap-vm` runs the full R10 sequence
unattended (the equivalent `charly update check-ubuntu-debootstrap-vm` rebuild also works,
since the bundle is folded into the Bundle map).

## debootstrap path

`charly vm build ubuntu-debootstrap` runs `debootstrap` inside the privileged
`ubuntu-debootstrap-builder` to build the rootfs, then writes a bootable disk +
cloud-init seed ISO. The bootstrap path is privileged + network-heavy
(`debootstrap` downloads the base packages from the Ubuntu mirror). The
Docker-Hub `/charly-distros:ubuntu` container base remains the faster path when you
don't need a VM disk.

## Cross-References

- `/charly-distros:ubuntu-debootstrap-builder` — the builder image this VM uses
- `/charly-distros:ubuntu-debootstrap` — the container equivalent of this bootstrap path
- `/charly-vm:debian-debootstrap-vm` — the Debian sibling bootstrap VM
- `/charly-vm:arch-cloud-vm` — the canonical cloud_image VM (BIOS/virtio-gpu/sizing rationale)
- `/charly-vm:vm` — VM lifecycle commands + BIOS/UEFI matrix
- `/charly-vm:vms-catalog` — VmSpec authoring reference

## When to Use This Skill

**MUST be invoked** when editing `ubuntu-debootstrap` or its check bed, or
authoring an Ubuntu VM. Invoke BEFORE reading source code or launching Explore agents.
