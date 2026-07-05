---
name: cachyos
description: |
  CachyOS bootstrap VM (kind:vm cachyos-vm) — source.kind: bootstrap via
  cachyos-pacstrap-builder + pacstrap, btrfs rootfs, uefi-insecure. Plus the
  disposable check-cachyos-vm deploy. Lives in the opencharly/distro-cachyos submodule.
  MUST be invoked before editing cachyos-vm or its check bed.
---

# cachyos (VM)

`source.kind: bootstrap` VM that builds a CachyOS rootfs from scratch via
`pacstrap` (using `/charly-distros:cachyos-pacstrap-builder`), then boots it under
libvirt/QEMU.

The `cachyos-vm` entity and its `check-cachyos-vm` disposable test bed live in
the **`opencharly/distro-cachyos`** repo (git submodule at **`box/cachyos`**),
all in that repo's unified `charly.yml`. The bed is a `disposable: true` deploy
(a check bed is just a deploy carrying `disposable: true` — there is no separate
bed kind), driven by `charly check run check-cachyos-vm`. Drive the VM lifecycle
from the submodule: `charly -C box/cachyos vm build cachyos-vm` +
`charly -C box/cachyos vm create cachyos-vm` (or `charly --repo opencharly/distro-cachyos …`).

## VM Configuration (from box/cachyos/charly.yml)

| Setting | Value |
|---|---|
| Source | `kind: bootstrap`, `builder: pacstrap`, `builder_image: cachyos-pacstrap-builder` |
| Distro | cachyos |
| rootfs | btrfs |
| Disk / RAM / CPU | 25G / 4G / 2 |
| Machine / firmware | q35 / uefi-insecure |
| Network | user mode |
| SSH | user `cachy`, port 12226, key_source generate |

The `cachyos` distro config (base packages, keyring, mirrors, repos) comes from
the embedded `distro: cachyos` build vocabulary baked into the `charly` binary
(`charly/charly.yml`), merged in by the unified loader.

## Check bed

`check-cachyos-vm` is a `disposable: true` deploy (`vm: {from: cachyos-vm,
disposable: true}`), so `charly -C box/cachyos check run check-cachyos-vm`
runs the full R10 sequence unattended (the equivalent `charly update
check-cachyos-vm` rebuild also works, since the deploy is folded into the
Bundle map).

`check-cachyos-gpu-vm` is the **full KDE GPU workstation** bed — it mirrors the
operator `cachyos-gpu` workstation's dual-desktop config and is the acceptance gate
for migrating it. A `cachyos-gpu-vm` guest (bootstrap VM, UEFI, `backend: libvirt`,
podman) receives a physical NVIDIA GPU via a VFIO `<hostdev>` and runs BOTH (a) a
bare-metal KDE Plasma SDDM seat as in-guest layers, AND (b) a nested
`selkies-kde-nvidia` streaming pod (real NVENC). It applies the `nvidia` toolkit +
the locally-vendored `nvidia-driver` kernel layer (whose `reboot: true` reboots the
guest mid-deploy so the open module loads on a clean boot and the boot-time
`nvidia-ctk cdi generate` writes `/etc/cdi/nvidia.yaml`), then the vm deploy plugin's
`OpPostApply` host-builds `selkies-kde-nvidia`, `charly vm cp-box
--rootless`s it into the guest user's podman as `localhost/charly-selkies-kde:latest`,
and runs the guest's own project-free `charly bundle from-box
localhost/charly-selkies-kde:latest selkies-kde` — a PERSISTENT in-guest `--user`
quadlet (GPU device auto-detected; `loginctl enable-linger` so it survives the
guest reboot the fresh-rebuild leg recreates). Deploy-scope checks run in-guest over
SSH: the quadlet is active + lingering, the stream answers on
`https://localhost:3000` (an in-guest `curl`, since the pod publishes `:3000` only
on the guest), and the nvidia encoder is queryable. The committed `cachyos-gpu-vm`
is **portable** — it carries NO hostdev block (a PCI address is host-specific);
generate one with `charly vm gpu list` and add it locally before a live GPU run. The
GPU-gated checks pass with an N/A note when no card is passed through, so the bed
runs anywhere. This is the R10 gate for the nested-pod-in-VM capability
(`/charly-internals:vm-deploy-target`). See `/charly-vm:vm` "GPU passthrough",
`/charly-distros:cuda`.

## pacstrap path

`charly vm build cachyos-vm` builds a bootable disk end-to-end. The
`vm_bootstrap.go` path uses the same `renderPacstrapExtraConf` helper as the
image path, which emits the per-repo `SigLevel` (required for GPGME) and an
`[options] Architecture = x86_64 x86_64_v3` directive (so `linux-cachyos`
passes the architecture check).

pacstrap installs `linux-cachyos` (x86_64_v3), mkinitcpio generates the
initramfs (its `autodetect` hook warns in the chroot and falls back to
all-modules — non-fatal), and a bootable `disk.qcow2` (~3.5 GB) + cloud-init
`seed.iso` are written. The Docker-Hub `/charly-distros:cachyos` container base
remains the faster path when you don't need a VM disk.

## Cross-References

- `/charly-distros:cachyos-pacstrap-builder` — the builder image this VM uses
- `/charly-distros:cachyos-pacstrap` — the container equivalent of this bootstrap path
- `/charly-vm:arch` — the canonical cloud_image VM (BIOS/virtio-gpu/sizing rationale)
- `/charly-vm:vm` — VM lifecycle commands + BIOS/UEFI matrix
- `/charly-vm:vms-catalog` — VmSpec authoring reference

## When to Use This Skill

**MUST be invoked** when editing `cachyos-vm` or its check bed, or authoring a
CachyOS VM. Invoke BEFORE reading source code or launching Explore agents.
