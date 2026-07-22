---
name: cloud-init-renderer
description: |
  Pure renderer from VmSpec + VmCloudInit to NoCloud seed ISO (user-data +
  meta-data + network-config). Covers composeUsers adopt-merge, SMBIOS vs
  cloud_init additive channels, xorriso ISO emission, and charly_install.strategy
  state machine. Source: sdk/vmshared/cloud_init_render.go, sdk/vmshared/cloud_init_iso.go, sdk/kit/charly_install.go.
  MUST be invoked before editing cloud-init emission paths.
---

# cloud-init-renderer

Host-side renderer producing NoCloud seed ISOs for cloud_image VMs (and bootc VMs that include the `cloud-init` layer). Pure transformation — given `VmSpec` + `VmCloudInit`, produces three files (user-data, meta-data, network-config) and packages them into an ISO 9660 image labeled `CIDATA` via xorriso.

Lives **host-side**, in the `charly` binary. The **guest-side** `/charly-distros:cloud-init` layer is complementary: it puts the cloud-init package into the bootc guest OS so that guest reads the seed ISO. The two sides cooperate across the host/guest boundary.

## Source files

| File | Contents |
|---|---|
| `sdk/vmshared/cloud_init_render.go` | `RenderCloudInit`, `ResolveKeyInjectionChannels`, `composeUsers`, `composePackages`, `composeRunCmd` |
| `sdk/vmshared/cloud_init_iso.go` | `WriteSeedISO` via xorriso; `genisoimage` + `mkisofs` fallbacks |
| `sdk/kit/charly_install.go` | `kit.EnsureCharlyInGuest` state machine (auto/scp/url/skip strategies) |
| `sdk/spec/cue_types_gen.go` (generated) | `VmCloudInit`, `VmCloudInitUser`, `VmCloudInitFile`, `VmCloudInitNetwork`, `VmCloudInitMirrors`, `VmCharlyInstall` |

## RenderCloudInit top-level

```go
func RenderCloudInit(spec *VmSpec, rt CloudInitRuntimeParams) (userData, metaData, networkConfig string, err error)
```

Returns three strings — the three files NoCloud expects on the seed ISO. The caller (`BuildCloudImage` or the vm deploy preflight) then calls `WriteSeedISO` to pack them.

**Egress validation gate.** Before returning, each rendered document is validated
against a CUE schema — user-data against the vendored Canonical cloud-config
schema (`#CloudConfig`), meta-data against `#CloudInitMeta`, network-config against
`#NetworkConfigV2` (via `ValidateEgress`). A malformed render fails here, so a
cloud-init that its own schema would reject never reaches the seed ISO. The gate
is owned by `/charly-internals:egress`.

## composeUsers (adopt-merge pattern)

Single most important function in this renderer. Produces the `users:` list in user-data.

**When `spec.Source.BaseUser` is non-empty** (cloud_image adopt pattern):

```yaml
users:
  - default                  # cloud-init sentinel: preserve distro's default account
  - name: <base_user>
    ssh_authorized_keys:
      - <pubkey>
```

No `useradd`, no sudoers write, no shell change — cloud-init interprets "name: X" on an existing account as "append ssh_authorized_keys". The parity is exact with the container-side `base_user:` + `user_policy: adopt` pattern (`/charly-image:image` "user_policy").

**When `BaseUser` is empty and `VmSSH.User` is non-empty** (create pattern):

```yaml
users:
  - default
  - name: <ssh_user>
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [wheel, sudo]
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - <pubkey>
```

Full account provisioning. Used by bootc VMs where no `base_user:` applies.

**When a user already appears in `spec.CloudInit.Users`**: the renderer appends the ssh pubkey to that existing entry instead of emitting a new one. Lets authors declare a user with specific sudo/groups/shell fields and still get the pubkey injected.

## ResolveKeyInjectionChannels

Applies the per-source-kind auto-defaults documented in `/charly-internals:vm-spec`:

```go
func ResolveKeyInjectionChannels(spec *VmSpec) (smbios bool, cloudInit bool) {
    if spec.SSH != nil && spec.SSH.KeyInjection != nil {
        // explicit overrides
        return spec.SSH.KeyInjection.SMBIOS == "enabled" (with "auto" = source-kind default),
               spec.SSH.KeyInjection.CloudInit == "enabled" (with "auto" = source-kind default)
    }
    // per-source-kind auto-defaults
    switch spec.Source.Kind {
    case "cloud_image":
        return true, true       // belt + suspenders
    case "bootc":
        return true, false      // cloud_init channel only activates with cloud-init layer
    }
}
```

**Both channels are additive** — when both are on, systemd-ssh-generator (SMBIOS path) and cloud-init (user-data path) both inject the key. Dedup happens in the guest's `authorized_keys`. There's no correctness issue with duplicate keys; the dual-injection pattern is the safe default.

## composePackages + composeRunCmd renderer defaults

The renderer prepends defaults to user-declared lists:

- `composePackages`: prepends `{openssh (or `openssh-server` on debian/ubuntu), curl, tar}` (deduplicated against user's `Packages`). Guarantees the guest has SSH server + download tools + tar for later layer application.
- `composeRunCmd`: prepends `{systemctl enable --now sshd (or ssh on debian/ubuntu)}`. Distro-specific user `runcmd:` entries can assume sshd is running.

User-supplied fields **extend** defaults; they don't replace them. Prevents the common footgun where an author puts `packages: [nginx]` and accidentally breaks SSH because they overrode the default list.

**Delivery is distro-branched (D15): `packages:` for most distros, a `runcmd:`-prepended `pacman -S --needed` for pacman-family.** On every distro EXCEPT the pacman family (arch/cachyos/manjaro/endeavouros), the composed package union rides the `packages:` cloud-config key as documented above. On a pacman-family distro, `packages:` is OMITTED entirely and the union is instead PREPENDED to `runcmd:` as `pacman -S --needed --noconfirm <union>` (before `composeRunCmd`'s sshd-enable line). This is an R10 bed finding: cloud-init's own package-install module invokes `pacman -S` WITHOUT `--needed`, so on an image that already ships the minimum set (e.g. every Arch cloud image) it unconditionally REINSTALLS them — reinstalling openssh re-triggers its post-install host-key-regen hook while the base image's own socket-activated sshd is already listening, racing a live key-file rewrite against new SSH connections (the observed "reset during `kex_exchange_identification`, guest otherwise idle" signature). apt/dnf installs are naturally no-op-idempotent when the package is already present, so only the pacman-family path needs the `--needed` rewrite; every other distro's render is byte-identical to the `packages:`-key form. The pacman-family check is `formatForDistroID(effectiveDistro(spec)) == "pac"`; `effectiveDistro` resolves `Source.Distro` when set, and additionally infers `"arch"` for a `cloud_image` source with `base_user: "arch"` and no explicit `distro:` (a narrowing of the pre-existing `composePackages` distro-switch fallback, never a behavior change for a caller that already got the Arch/Fedora shape) — every OTHER empty-distro image stays on the safe, unchanged `packages:`-key path. See `sdk/vmshared/cloud_init_render.go`'s `effectiveDistro`/`composePackages` doc comments for the full narrowing proof.

## WriteSeedISO

```go
func WriteSeedISO(userData, metaData, networkConfig string, outputPath string) error
```

Writes an ISO 9660 image whose volume identifier is `CIDATA` (the shared
`vmshared.cloudInitVolumeID`). It MUST be uppercase: ISO 9660 / ECMA 119
d-characters are `A-Z 0-9 _` only, so a lowercase label makes xorriso warn on
every VM boot. cloud-init still finds it — its NoCloud datasource searches both
`LABEL=<fs_label>.upper()` and `.lower()`, with `fs_label` defaulting to
`cidata`. Tool preference order:

1. `xorriso` (preferred — modern, scriptable).
2. `genisoimage` (legacy but widely available).
3. `mkisofs` (oldest fallback).

Clean error when none are present, with distro-appropriate install recipe (`dnf install xorriso`, `pacman -S libisoburn`, `apt-get install xorriso`).

The ISO is mounted by QEMU as a CD-ROM; cloud-init's NoCloud datasource reads `/dev/sr0` at first boot.

## EnsureCharlyInGuest (charly_install.strategy state machine)

Runs post-boot inside the vm deploy preflight (the `candy/plugin-deploy-vm` plugin's `OpPrepareVenue`, via `kit.EnsureCharlyInGuest` in `sdk/kit/charly_install.go`) after cloud-init completes, BEFORE the plugin walks the plans. Dispatches on `spec.CloudInit.CharlyInstall.Strategy`:

| Strategy | Action |
|---|---|
| `auto` / `scp` | `scp $(os.Executable()) guest:/usr/local/bin/charly; chmod +x` |
| `url` | ssh-execute `curl -L <url> -o /usr/local/bin/charly && sha256sum -c` (verified against `VmCharlyInstall.Checksum`) |
| `skip` | `ssh 'which charly'` — fails if missing, returns early if present |

Idempotent. If `charly` is already present at the target version, the function returns without re-scp'ing. See `/charly-internals:vm-deploy-target` for how this plugs into the overall deploy flow.

## Network config

`VmCloudInitNetwork.Ethernets` passes through to cloud-init's network-config v2 as-is. When unset, the renderer emits an empty network-config (cloud-init defaults to DHCP on every virtio-net interface). Good default; override only for static-IP deployments.

## SMBIOS vs cloud_init can coexist

Explicitly supported — not either/or. `VmKeyInjection.SMBIOS: enabled` + `VmKeyInjection.CloudInit: enabled` simultaneously is the default for cloud_image VMs. Rationale: belt-and-suspenders (SMBIOS via systemd-ssh-generator v250+, cloud-init via user-data — both paths exist on modern Linux). No duplication cost.

## Cross-References

- `/charly-internals:vm-spec` — `VmCloudInit`, `VmSSH.KeyInjection`, `VmCharlyInstall` types
- `/charly-internals:libvirt-renderer` — SMBIOS-channel emission (domain XML side)
- `/charly-internals:vm-deploy-target` — `EnsureCharlyInGuest` caller; SSH/cloud-init readiness waits
- `/charly-vm:vm` — command-family; cloud-init flow
- `/charly-vm:vms-catalog` — YAML-authoring reference
- `/charly-vm:arch-cloud-vm` — `charly_install.strategy: auto` worked example; adopt-user pattern
- `/charly-distros:cloud-init` — **guest-side pairing**: the cloud-init package installed inside bootc images reads the seed ISO this renderer produces
