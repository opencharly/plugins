---
name: vm-spec
description: |
  Go type reference for VmSpec and the discriminated-union source types
  (VmSource cloud_image | bootc | clone | imported | bootstrap). Documents every
  field, validation rules, and the adopt-user decision. Source files:
  sdk/spec/cue_types_gen.go (generated), sdk/schema/vm.cue, sdk/vmshared/.
  MUST be invoked before editing VmSpec Go code or authoring vm.yml entries.
---

# vm-spec

Go type reference for the VM surface. `VmSpec` + `VmSource` + `VmChecksum` + `VmNetwork` + `VmSSH` + `VmKeyInjection` + `VmCloudInit` + `VmCharlyInstall` are the canonical types that drive `charly vm build`, `charly vm create`, and `charly bundle add vm:<name>`. This skill is the authoritative Go reference — field semantics, defaults, validation rules, migration history. The YAML-authoring companion is `/charly-vm:vms-catalog`.

## Source files

| File | Contents |
|---|---|
| `sdk/spec/cue_types_gen.go` (generated; charly-name aliases in `sdk/spec/charly_names.go`) | `VmSpec` (= `Vm`), `VmSource`, `VmChecksum`, `VmNetwork`, `VmSSH`, `VmKeyInjection` |
| `sdk/spec/cue_types_gen.go` (generated) | `VmCloudInit`, `VmCloudInitUser`, `VmCloudInitFile`, `VmCloudInitNetwork`, `VmCloudInitMirrors`, `VmCharlyInstall` |
| `sdk/vmshared/libvirt_yaml.go` | `LibvirtDomain` + 30+ sub-types (features, CPU, clock, devices, etc.) |
| `sdk/schema/vm.cue` + `cue_kind_vm.go` | `#Vm` — the closed CUE schema validating `VmSpec` + the `#LibvirtDomain`/`#VmCloudInit` subtrees (registered in the per-kind CUE registry; the Go VM/libvirt validators were deleted) |

## VmSpec (top-level shape)

```go
type VmSpec struct {
    Source VmSource       // discriminated union: kind = cloud_image | bootc
    DiskSize string       // "20G", "10 GiB", "1T" — virtual size; the qcow2 is lazily/sparsely allocated
    Ram      string       // "4G", "8192M"
    Cpus     int
    Machine  string       // q35 | virt | i440fx — default: host-native
    Firmware string       // bios | uefi-insecure | uefi-secure — default: bios
    Backend  string       // auto | libvirt | qemu — pins the backend for this entity
    Autostart bool        // libvirt domain autostart (libvirt backend only)
    Network  *VmNetwork
    SSH      *VmSSH
    CloudInit *VmCloudInit
    Libvirt  *LibvirtDomain
}
```

Every field except `Source`, `CloudInit`, and `Source`-branch-specific subfields applies equally to both source kinds — the parity guarantee. Anything configurable for cloud_image VMs is configurable for bootc VMs, and vice versa.

### Autostart (boot-start)

`autostart: true` sets libvirt's per-domain autostart flag (`DomainSetAutostart`, in `runVmSpecCreate` after define). Because VMs run under `qemu:///session`, that flag only fires at host boot once the session daemon is running — and there is no portable user-level `virtqemud.socket` to socket-activate it (Arch/CachyOS ships none). So `ensureBootAutostartPrereqs` (`candy/plugin-vm/vm.go`) (a) runs `loginctl enable-linger <user>` (idempotent) and (b) writes + enables a per-VM user systemd oneshot `charly-autostart-<domain>.service` that runs `virsh -c qemu:///session start <domain>` at boot (`WantedBy=default.target`); virsh spawns the session daemon on demand and starts the already-defined domain — deterministic and cross-distro. `charly vm destroy` removes the unit (`removeAutostartUserUnit`). The libvirt flag is a domain property (not XML), so it survives `DomainDefineXML` redefinitions; `runVmSpecCreate` re-asserts both on every create/rebuild. The `#Vm` CUE schema rejects `autostart: true` with `backend: qemu` (`if autostart { backend: "auto" | "libvirt" }`). Additive optional field — no schema-version bump.

`DiskSize` is the **virtual** size: the bootstrap path's `truncate` + `qemu-img convert -O qcow2` (no `preallocation`) produces a sparse qcow2 that grows on demand, so `disk_size: 1T` costs only the bytes actually written.

### virtiofs shares — guest-user idmap

A `libvirt.devices.filesystems[]` entry with `driver: virtiofs` +
`accessmode: passthrough` + a host-path `source` is auto-given a guest-user
`<idmap>` at render time so the share is owned by the guest's interactive user
(uid 1000), not guest-root. This is what makes `source: /home/<you>` →
`target: workspace` usable as the SSH user inside the guest. Mechanism +
the exact id partition live in `/charly-internals:libvirt-renderer` "virtiofs
guest-user idmap"; shared-memory auto-pairing is in the same skill.

## VmSource (discriminated union)

```go
type VmSource struct {
    Kind string    // "cloud_image" | "bootc"

    // cloud_image branch:
    URL      string
    Checksum VmChecksum
    Cache    string
    BaseUser string       // adopt-user pattern — see below

    // bootc branch:
    Image      string     // `candy:` image entry name (carries base:/from:)
    Transport  string     // registry | containers-storage | oci | oci-archive
    Rootfs     string     // ext4 | xfs | btrfs
    RootSize   string     // "10G" — caps root partition, rest unpartitioned
    KernelArgs string
}
```

`Kind` is the discriminator. The `#VmSource` CUE disjunction (`schema/vm.cue`) enforces that exactly one branch's required fields are populated and forbids cross-branch fields (each arm pins `kind` and marks the others `_|_`).

### Adopt-user decision (BaseUser)

`BaseUser` mirrors the container-side `base_user:` + `user_policy: adopt` pattern. When set:

1. `/charly-internals:cloud-init-renderer::composeUsers` emits `users: [default, {name: <base_user>, ssh_authorized_keys: [...]}]` — merge-by-name, no `useradd`.
2. `spec.ssh.user` defaults to `BaseUser`.
3. cloud-init appends the pubkey to `~<base_user>/.ssh/authorized_keys` without touching sudoers/shell/home.

Common values: `arch` (Arch cloud image), `ubuntu` (Ubuntu Cloud), `fedora` (Fedora Cloud), `debian` (Debian Cloud), `cloud-user` (CentOS Cloud).

Leave empty **only** when the image has no default account — then declare a custom user in `spec.cloud_init.users`.

## VmSSH / VmKeyInjection

```go
type VmSSH struct {
    User         string   // default: cloud_image → "charly" OR base_user; bootc → "root"
    Port         int      // default: 2222
    KeySource    string   // auto | generate | none | <abs-path>
    KeyInjection *VmKeyInjection
}

type VmKeyInjection struct {
    SMBIOS    string  // auto | enabled | disabled
    CloudInit string  // auto | enabled | disabled
}
```

**Dual-channel key injection is additive.** Per-source-kind auto-defaults when `KeyInjection` is nil:

- `cloud_image` → `{smbios: enabled, cloud_init: enabled}` — belt + suspenders; cloud-init seed ISO is always emitted anyway.
- `bootc` → `{smbios: enabled, cloud_init: disabled}` — cloud-init seed ISO only emits when the guest has the `cloud-init` layer.

Having both channels on simultaneously is the safe default; there's no duplication cost at the guest (systemd-ssh-generator dedups entries in `authorized_keys`).

## VmCloudInit (structured intent)

The renderer combines structured fields with renderer defaults:

- `Packages`: prepended with `{openssh, curl, tar}`.
- `RunCmd`: prepended with `{systemctl enable --now sshd}` so distro-specific setup can assume sshd is running.
- `Users`: the `VmSSH.User` account is auto-injected unless already present; if present, the renderer appends the ssh pubkey to the user's existing entry.

`Extra` is a raw-YAML escape hatch merged after structured fields. Prefer structured fields; `Extra` exists for long-tail cloud-init options the schema doesn't cover.

## VmCharlyInstall strategies

```go
type VmCharlyInstall struct {
    Strategy string  // auto | scp | url | skip
    URL      string  // when Strategy == "url"
    Checksum string  // "sha256:<hex>" for url strategy
}
```

| Strategy | Behavior |
|---|---|
| `auto` (default) | scp the local `charly` binary (`os.Executable()`) into the guest post-boot via the vm deploy plugin's `OpPrepareVenue` (`kit.EnsureCharlyInGuest`) |
| `scp` | explicit form of auto |
| `url` | cloud-init runcmd downloads charly from URL at first boot |
| `skip` | user manages charly install; the vm deploy plugin's `OpPrepareVenue` verifies presence only |

## Validation (sdk/schema/vm.cue)

The closed `#Vm` CUE schema (registered via `cue_kind_vm.go`) enforces every VmSpec
invariant — there is no Go VM validator. Key checks:

- `source.kind` ∈ {`cloud_image`, `bootc`, `clone`, `imported`, `bootstrap`}; the
  `#VmSource` disjunction requires each arm's fields and forbids cross-arm fields.
- `firmware:` ∈ {`bios` (default), `uefi-insecure`, `uefi-secure`}; `uefi-secure` ⇒
  `machine ≠ i440fx` AND requires an explicit `libvirt.features.smm: true`.
- `network.mode:` ∈ {`user` (default), `bridge`, `nat`, `network`}; `bridge` ⇒ `bridge:` set.
- `ssh.port` ⊕ `ssh.port_auto` (mutually exclusive); `ssh.key_source:` ∈ {`auto`,
  `generate`, `none`} or an absolute path; `ssh.key_injection.{smbios,cloud_init}` ∈
  {`auto`, `enabled`, `disabled`}.
- the `#LibvirtDomain` subtree is modeled + closed in the same schema (enums/ranges/
  PCI-hex + `cpu.mode:custom ⇒ model`); see `/charly-internals:libvirt-renderer`.

Failed validation → hard load-time error (the closed schema also rejects unknown
keys/typos); `charly box validate` runs the full concrete check.

## Migration from legacy VmConfig

The legacy `VmConfig` type + `BoxConfig.Vm` + `BoxConfig.Libvirt` + `ResolvedBox.Vm` + `LabelVm` + `LabelLibvirt` were **all deleted** in the hard cutover. The current shape is a name-first `<name>: {vm: {…}}` node. Forensic field mapping (target column in the current node form):

| Legacy location | Current location |
|---|---|
| `box.bootc: true` + `box.vm.disk_size` | `<name>.vm.source.kind: bootc` + `<name>.vm.disk_size` |
| `box.vm.ssh_port` | `<name>.vm.ssh.port` |
| `box.vm.ram`, `.cpus`, `.rootfs`, `.root_size`, `.kernel_args` | `<name>.vm.ram`, `.cpu` (yaml key now singular), `source.rootfs`, `source.root_size`, `source.kernel_args` |
| `box.vm.firmware` | `<name>.vm.firmware` |
| `box.vm.network` (string) | `<name>.vm.network.mode` |
| `box.libvirt: ["<xml>", …]` (list of strings) | `<name>.vm.libvirt.snippets: […]` + structured `libvirt.devices.*` |

`charly migrate` does **not** perform this mapping any more — the harvest lived in the migration chain removed at the `2026.186.2323` baseline reset, so a config still carrying the legacy fields predates the schema floor (`2026.174.1100`) and is unmigratable; re-author it by hand. See `/charly-build:migrate` for the floor/HEAD gate and `/charly-internals:cutover-policy` for the policy.

## Cross-References

- `/charly-vm:vms-catalog` — YAML-authoring companion (when to pick cloud_image vs bootc, adopt pattern, step-by-step recipes)
- `/charly-internals:libvirt-renderer` — `LibvirtDomain` rendering + pure render functions
- `/charly-internals:cloud-init-renderer` — `RenderCloudInit`, `composeUsers`, seed ISO
- `/charly-internals:vm-deploy-target` — the external vm deploy + the vm deploy plugin consuming the resolved VmSpec via the host prepare hook
- `/charly-internals:ovmf` — `ResolveOvmfForSpec` reads `spec.Firmware`
- `/charly-internals:cutover-policy` — why the legacy surface was deleted in one PR
- `/charly-vm:vm` — command-family skill; reads vm.yml through VmSpec
- `/charly-build:migrate` — `charly migrate` command
- `/charly-internals:go` — Go CLI development overview
