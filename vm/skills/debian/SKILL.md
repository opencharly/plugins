---
name: debian
description: |
  Debian bootstrap VM (kind:vm debian-debootstrap) — source.kind: bootstrap via
  debian-debootstrap-builder + debootstrap, ext4 rootfs, uefi-insecure. Plus the
  disposable check-debian-debootstrap-vm deploy. Lives in the opencharly/distro-debian submodule.
  MUST be invoked before editing debian-debootstrap or its check bed.
---

# debian (VM)

`source.kind: bootstrap` VM that builds a Debian rootfs from scratch via
`debootstrap` (using `/charly-distros:debian-debootstrap-builder`), then boots it
under libvirt/QEMU.

The `debian-debootstrap` VM entity and its `check-debian-debootstrap-vm` disposable
test bed live in the **`opencharly/distro-debian`** repo (git submodule at
**`box/debian`**), all in that repo's unified `charly.yml`. The bed is a
`disposable: true` deploy (a check bed is just a deploy carrying `disposable: true`
— there is no separate bed kind), driven by `charly check run
check-debian-debootstrap-vm`. Drive the VM lifecycle from the submodule:
`charly -C box/debian vm build debian-debootstrap` +
`charly -C box/debian vm create debian-debootstrap` (or
`charly --repo opencharly/distro-debian …`).

## VM Configuration (from box/debian/charly.yml)

| Setting | Value |
|---|---|
| Source | `kind: bootstrap`, `builder: debootstrap`, `builder_image: debian-debootstrap-builder` |
| Distro | debian |
| rootfs | ext4 |
| Disk / RAM / CPU | 20G / 4G / 2 |
| Machine / firmware | q35 / uefi-insecure |
| Network | user mode |
| SSH | user `debian`, port 12227, key_source generate |

The `debian` distro config (debootstrap suite/mirror, base packages, bootloader
template) comes from the embedded `distro:` build vocabulary baked into the
charly binary, which the unified loader makes available to the submodule's
`charly.yml` automatically — no explicit import needed.

## Check bed

`check-debian-debootstrap-vm` is a `disposable: true` deploy
(`vm: {from: debian-debootstrap, disposable: true}`), so
`charly -C box/debian check run check-debian-debootstrap-vm` runs the full R10 sequence
unattended (the equivalent `charly update check-debian-debootstrap-vm` rebuild also works,
since the bundle is folded into the Bundle map).

## debootstrap path

`charly vm build debian-debootstrap` runs `debootstrap` inside the privileged
`debian-debootstrap-builder` to build the rootfs, then writes a bootable disk +
cloud-init seed ISO. The bootstrap path is privileged + network-heavy
(`debootstrap` downloads the base packages from the Debian mirror). The
Docker-Hub `/charly-distros:debian` container base remains the faster path when you
don't need a VM disk.

## Cross-References

- `/charly-distros:debian-debootstrap-builder` — the builder image this VM uses
- `/charly-distros:debian-debootstrap` — the container equivalent of this bootstrap path
- `/charly-vm:ubuntu` — the Ubuntu sibling bootstrap VM
- `/charly-vm:arch` — the canonical cloud_image VM (BIOS/virtio-gpu/sizing rationale)
- `/charly-vm:vm` — VM lifecycle commands + BIOS/UEFI matrix
- `/charly-vm:vms-catalog` — VmSpec authoring reference

## When to Use This Skill

**MUST be invoked** when editing `debian-debootstrap` or its check bed, or
authoring a Debian VM. Invoke BEFORE reading source code or launching Explore agents.
