---
name: vms-catalog
description: |
  Authoring reference for kind:vm entities in vm.yml. Parallel to /charly-image:layer and /charly-image:image.
  Covers the VmSpec schema, source.kind discriminator (cloud_image vs bootc),
  base_user adopt pattern, and step-by-step recipes for both source kinds.
  MUST be invoked before authoring or editing vm.yml entries.
---

# vms

`vm.yml` is the authoring surface for `kind: vm` entities — VM primitives that pair with either a remote cloud-image URL (`source.kind: cloud_image`) or an in-repo bootc container image (`source.kind: bootc`). Loaded through `charly.yml`'s `import:` (or inline under its root). Entries are resolved by `LoadUnified` into `VmSpec` Go types (generated in `sdk/spec/`) and consumed by `charly vm build`, `charly vm create`, and `charly bundle add vm:<name>`.

The VM surface parallels the `candy:` image surface: one YAML entry per entity, kind-keyed, discovered through includes. The Go types that back it live in `/charly-internals:vm-spec`; the rendering paths in `/charly-internals:libvirt-renderer` and `/charly-internals:cloud-init-renderer`.

## File layout

```yaml
# vm.yml
vms:
  <name>:
    source:
      kind: cloud_image | bootc
      # cloud_image branch:
      url: https://…
      checksum: { type: sha256, value?: <hex> }
      base_user: arch                     # adopt this account (see Adopt pattern below)
      cache: ~/.cache/charly/vm-images/       # optional override
      # bootc branch:
      box: <candy: image entry name>           # `box:` source field → a `candy:` image carrying base:/from:
      transport: registry | containers-storage | oci | oci-archive
      rootfs: ext4 | xfs | btrfs
      root_size: 10G                      # optional cap; rest of disk stays unpartitioned
      kernel_args: "…"
    # Hardware (both branches):
    disk_size: 20G | "10 GiB" | 1T         # VIRTUAL size; qcow2 is lazily/sparsely allocated (grows on demand)
    ram: 4G | "8192M"
    cpus: 4
    machine: q35 | virt | i440fx           # default: host-native
    firmware: bios | uefi-insecure | uefi-secure  # default: bios
    backend: auto | libvirt | qemu         # default: auto
    autostart: true                        # start at host boot (libvirt only — see below)
    # Network:
    network:
      mode: user | bridge | nat
      bridge: br0                          # only when mode=bridge
      mac: "52:54:…"                       # optional pin; default stable-from-name
      port_forwards: ["8080:80", …]        # additive to SSH forward
    # SSH + key injection:
    ssh:
      user: arch | root | …                # defaults: cloud_image→"charly", bootc→"root"
      port: 2222                           # host port → guest :22
      key_source: auto | generate | none | /abs/path.pub
      key_injection:
        smbios: auto | enabled | disabled
        cloud_init: auto | enabled | disabled
    # Cloud-init (structured intent):
    cloud_init:
      timezone: UTC
      packages: [sudo, spice-vdagent, …]
      runcmd: ["…", …]
      charly_install:
        strategy: auto | none
    # Libvirt XML knobs (see /charly-internals:libvirt-renderer):
    libvirt:
      devices:
        channels: [{type: unix, name: org.qemu.guest_agent.0}]   # qemu-guest-agent
        graphics: […]
        video: [{model: virtio, vram: 65536, heads: 1, accel3d: false}]
        rng: [{model: virtio, backend: /dev/urandom}]
        memballoon: {model: virtio}
        hostdevs: […]                                            # PCI passthrough (charly vm gpu list)
        filesystems:                                             # virtiofs/9p host↔guest shares
          - {driver: virtiofs, accessmode: passthrough, source: /home/me, target: workspace}
      # memory_backing is auto-paired (memfd + shared) for any virtiofs share
```

### autostart — start the VM at host boot

`autostart: true` sets libvirt's domain autostart flag. Because charly VMs run under
`qemu:///session` (no portable user-level `virtqemud.socket` to socket-activate at
boot), `charly vm create` also enables `loginctl enable-linger` (idempotent) and
writes + enables a per-VM user oneshot `charly-autostart-<domain>.service` that
`virsh -c qemu:///session start`s the domain at boot (`charly vm destroy` removes it).
**Requires `backend: libvirt`** — validation rejects `autostart: true` with
`backend: qemu`. Reapplied on every `charly vm create` / `charly update`. Pair with a
1 TB+ `disk_size` freely — the qcow2 is sparse, so a large virtual disk costs only
the bytes written.

### filesystems — virtiofs host directory shares

`libvirt.devices.filesystems[]` exposes a host directory inside the guest:
`{driver: virtiofs, accessmode: passthrough, source: <host dir>, target: <tag>}`.
The shared-memory backing virtiofs requires (`memfd`/`shared`) is **auto-paired**
— you don't declare `memory_backing` yourself. The guest mounts the `target:` tag
with the `/charly-distros:workspace-mount` layer (a systemd `.mount` unit for the
`workspace` tag → `/workspace`) or any `mount -t virtiofs <tag> <dir>`.

### graphics `listen:` field — three accepted shapes

`graphics[].listen` is how you control the `<listen>` children of a
`<graphics>` element. Three equivalent shapes, all unmarshal to the same
internal list:

```yaml
# (1) Scalar address (shorthand for one TCP listener):
listen: 127.0.0.1

# (2) Single map (explicit type control — socket | address | network):
listen:
  type: socket              # libvirt auto-allocates the UNIX socket path
# or:
listen:
  type: address
  address: 127.0.0.1

# (3) List of maps (multiple listeners on one <graphics>):
listen:
  - type: socket
  - type: address
    address: 127.0.0.1
```

**Prefer `type: socket` for charly-managed VMs.** virt-manager and
`remote-viewer --connect qemu+ssh://…` auto-forward UNIX sockets over
the libvirt RPC channel — GUI clients work out of the box against a
remote libvirt with zero `ssh -L` setup. TCP loopback listeners are
never auto-tunneled, by design. See `/charly-vm:arch`
"Connecting from a remote workstation".

## source.kind: cloud_image

Use when the VM is built from an **externally published qcow2** (Arch cloud image from pkgbuild.com, Fedora Cloud, Ubuntu Cloud, Debian Cloud, CentOS Cloud, etc.). The build pipeline fetches the URL, integrity-checks it via sha256 (sidecar auto-resolved when `checksum.value` is empty), creates a qcow2 overlay at `spec.disk_size`, renders a NoCloud seed ISO, and hands off to libvirt/QEMU.

Canonical example: `/charly-vm:arch`. Only existing cloud_image VM in the repo — **read it before authoring another one**. It documents the non-obvious decisions learned the hard way:

- **BIOS firmware is usually the right default.** Distribution cloud images ship both a BIOS boot partition and an EFI System Partition, but the ESP's bootloader binary often has an **embedded grub.cfg that predates the maintainer's latest `/etc/default/grub`** (Arch's upstream issue with `fbcon=nodefer`). BIOS boot reads `/boot/grub/grub.cfg` directly from the root fs, which is always current.
- **virtio-gpu, not QXL.** See `/charly-internals:libvirt-renderer` "video model choice" — virtio-gpu is the modern default for Linux guests.
- **Generous resource sizing.** `pacman -S spice-vdagent` pulls in GTK3 + X11 (~200 MB download, ~1 GB installed); running at 2 GiB RAM stalls cloud-init. Size for the workload: 8 GiB / 4 cpus is reasonable for a workstation-class dev VM.

### Authoring a new cloud_image VM

1. Find the upstream qcow2 URL + verify a sha256 sidecar exists (<url>.SHA256 / .sha256 / .sha256sum).
2. Identify the **pre-existing user account** in the upstream image (`arch`, `ubuntu`, `fedora`, `debian`, `cloud-user`, etc.). This becomes `source.base_user:` — triggers the adopt pattern described below.
3. Start from `/charly-vm:arch` as a template. Change `url`, `base_user`, distro-specific cloud_init `package:` and `runcmd:`.
4. Pick firmware: default to `bios` unless the upstream image explicitly requires UEFI (e.g., secure boot lock-in).
5. Run `charly vm build <name>` — observe the fetched qcow2 sha256 + rendered seed ISO path.
6. Run `charly vm create <name>` + `charly vm ssh <name>` to verify cloud-init completed.

## source.kind: bootc

Use when the VM is built from an **in-repo bootc container image** (a `candy:` image entry with `bootc: true`). `charly vm build` runs `bootc install to-disk --via-loopback` inside a privileged container to produce the qcow2/raw disk.

No bootc VM ships in the repo today; a bootc `vms:` entry pairs a `candy:` image carrying `bootc: true` with the VM hardware spec. By convention a `-bootc` suffix marks the bootc VM entity (distinguished from an equivalent container-form deploy by the `vms:` namespacing, not by the name).

### Authoring a new bootc VM

1. Ensure the paired container image has `bootc: true` declared and builds cleanly.
2. Add a `vms:` entry with `source.kind: bootc` + `source.image: <entry-name>`.
3. Size disk/ram/cpus for the workload (see the relevant per-pod or `/charly-distros:<name> / /charly-languages:<name> / /charly-infrastructure:<name> / /charly-tools:<name>` skill's VM Configuration section for the authoritative numbers).
4. Run `charly vm build <vm-name>`. See `/charly-vm:vm` known-caveats section for bootc-specific gotchas (rootful storage split, nested-container `--transport containers-storage`, loopback device mount namespace).

## Adopt pattern: base_user (cloud_image only)

Mirrors the container-side `base_user:` + `user_policy: adopt` pattern documented in `/charly-image:image` "user_policy". The key insight: **don't recreate accounts cloud-init already shipped** — just append the SSH pubkey and move on.

When `source.base_user:` is set, the cloud-init renderer (`/charly-internals:cloud-init-renderer::composeUsers`) emits a merge-by-name entry:

```yaml
# Rendered user-data
users:
  - default
  - name: <base_user>
    ssh_authorized_keys:
      - ssh-ed25519 AAAA…
```

cloud-init interprets `users: [default, {name: <base_user>}]` as "keep the distro's default account untouched, append SSH key to the named account". Result: no `useradd`, no sudoers rewrite, no shell change, no home-directory relocation — just the pubkey lands in `~<user>/.ssh/authorized_keys` on first boot.

`spec.ssh.user` defaults to `source.base_user`, so `charly vm ssh <name>` connects as the adopted account without extra declaration.

Leave `base_user:` empty **only** when the upstream has no default account — in which case author a full custom user entry in `cloud_init.users:` with sudo/groups/shell fields. Don't do this when adopting works; `useradd`-at-first-boot races with other cloud-init modules and is harder to reason about.

## charly_install.strategy: auto (cloud_image)

`charly_install.strategy: auto` in `cloud_init:` wires `charly`'s in-guest installer (`/charly-internals:cloud-init-renderer` → emitted `runcmd:` entries) so the provisioned VM comes up with `charly` already installed. Lets `charly bundle add vm:<name>` apply host-deploy-style layer recipes inside the VM over SSH without a bootstrap round-trip. See `/charly-internals:cloud-init-renderer` for the emission + handshake.

`strategy: none` skips the step entirely — useful when the VM will be managed by something other than `charly` after provisioning.

## Validation rules

Load-time errors raised by the closed `#Vm` CUE schema (`sdk/schema/vm.cue`, see `/charly-internals:vm-spec`):

- `source.kind` must be one of `cloud_image`, `bootc`, `clone`, `imported`, `bootstrap`; each arm requires its own fields and forbids the others'.
- `cloud_image` requires `url:`; `bootc` requires the `box:` source field resolving to a `candy:` image entry (carrying `base:`/`from:`); `clone` requires `from_vm:`+`from_snapshot:`; `imported` requires `libvirt_name:`+`disk_path:`+`disk_format:`; `bootstrap` requires `builder:`+`distro:`.
- `firmware:` must be one of `bios`, `uefi-insecure`, `uefi-secure`; `uefi-secure` additionally requires an explicit `libvirt.features.smm: true`.
- `network.mode:` must be one of `user`, `bridge`, `nat`, `network`.
- `ssh.key_source:` must parse as `auto`, `generate`, `none`, or an absolute path; `ssh.port` and `ssh.port_auto` are mutually exclusive.
- `ssh.key_injection.smbios` / `.cloud_init` must be one of `auto`, `enabled`, `disabled`.
- the `libvirt:` subtree is modeled + closed by `#LibvirtDomain` in the same schema — unknown keys and bad enums fail fast.

## Migration from legacy (box.bootc / box.vm / box.libvirt)

Projects predating this schema had three coupled fields on image entries (`candy:` nodes carrying `base:`/`from:`): `bootc: true`, `vm: {...}`, `libvirt: [...]`. All three were deleted in the hard cutover. Conversion is one-shot:

```bash
charly migrate
```

Idempotent. Harvests the legacy fields into `vms:` entries, preserving any pre-existing `vms:` keys. See `/charly-build:migrate` for the full command reference and `/charly-internals:cutover-policy` for why hard-cutover was the chosen policy.

## Cross-References

- `/charly-vm:vm` — the `charly vm build/create/start/stop/ssh/console` command family
- `/charly-build:migrate` — `charly migrate` conversion from legacy
- `/charly-core:deploy` — `charly bundle add vm:<name>` for in-guest layer application
- `/charly-vm:arch` — canonical cloud_image VM
- `/charly-internals:vm-spec` — Go type reference
- `/charly-internals:libvirt-renderer` — libvirt XML emission
- `/charly-internals:cloud-init-renderer` — NoCloud seed ISO + user-data emission
- `/charly-internals:ovmf` — UEFI firmware path resolution (when `firmware:` ≠ `bios`)
- `/charly-internals:vm-deploy-target` — the external vm deploy in the InstallPlan pipeline
- `/charly-internals:cutover-policy` — Hard Cutover by Default policy
- `/charly-distros:cloud-init` — guest-side cloud-init layer (pairs with host-side `cloud_init:` emission)
- `/charly-distros:qemu-guest-agent` — virtio-serial channel for host↔guest comms

## Live-deploy verification is mandatory (see `/charly-check:check` 10 standards)

Changes that touch this verb's output must reach a healthy deployment on a target explicitly marked `disposable: true` (see `/charly-internals:disposable`). Use `charly update <name>` to destroy + rebuild unattended on any disposable target. Never experiment on a non-disposable deploy — set up a disposable one first with `charly bundle add <name> <ref> --disposable` or mark a VM in vm.yml.

**After committing the source-level fix, `charly update` the disposable target ONCE MORE from clean and re-run the full verification.** A fix that passes only on a hand-patched target is not a real fix — it's a regression waiting for the next unrelated rebuild. Paste BOTH the exploratory-pass output and the fresh-rebuild-pass output into the conversation.

Unit tests + a clean compile are necessary but not sufficient. See CLAUDE.md R1–R10.
