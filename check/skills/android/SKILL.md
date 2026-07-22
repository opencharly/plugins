---
name: android
description: |
  MUST be invoked before any work involving: the `kind: android` schema kind, a `target: android` deploy (the external `deploy:android` substrate), the `apk:` layer package format (installing Android apps declaratively), the android deploy preresolver, an in-pod emulator OR a remote/physical adb-endpoint device, or nested `pod → android` deployment. The first-class Android device + app surface that sits above the `adb:`/`appium:` check verbs.
---

# kind: android + the `apk` package format

## Overview

Android is a first-class deploy **substrate** in `charly`, modeled on `kind: k8s`.
Two cooperating concepts:

- **`kind: android`** — a DEVICE (the substrate). Either an in-pod emulator
  (referenced by `image:`) or a remote/physical adb endpoint (`adb:
  {host: <host:port>}`). The analogue of `kind: k8s` (the cluster).
- **`apk` package format** — Android apps declared in LAYERS (NOT a kind),
  parallel to `package:`/`aur:`. A `target: android` deploy applies its layers'
  `apk:` packages onto the device. The app is the deployable workload, the way a
  `candy:` image (a `candy:` node carrying `base:`/`from:`) is the workload for a pod/k8s deploy.

This sits ABOVE the device-interaction verbs: the `adb:` (`/charly-check:adb`)
and `appium:` (`/charly-check:appium`) declarative check verbs drive a running
device; `kind: android` + `target: android` declaratively describe a device and
the apps installed on it. The install machinery is shared — see "One installer
(R3)".

## `kind: android` — the device

```yaml
# charly.yml — each device is its own name-first entity; the android: value holds
# the WHOLE body — scalars AND the non-scalar google_account:/adb: fields, inline
pixel9a-36:                          # in-pod emulator device
    android:
        box: android-emulator       # `box:` source field → the `candy:` image that BAKES the emulator + system image
        device: pixel_9a             # informational (documents the baked AVD profile)
        api_level: 36                # informational (the API level is a BUILD property of box:)
        google_account:              # credential-store secret-key refs for apkeep google-play
            email_secret: GOOGLE_ACCOUNT_EMAIL
            token_secret: GOOGLE_AAS_TOKEN

my-phone:                            # remote/physical device
    android:
        serial: 192.168.1.50:5555
        adb:                         # an adb SERVER addr (a host running `adb connect`)
            host: 192.168.1.50:5555
```

**Device source is exclusive: `image:` XOR `adb:`.**

- **`image:` (in-pod)** — apkeep runs INSIDE the emulator pod (`engine exec`);
  the pod's own adb installs onto its emulator. Needs nothing extra on the host.
- **`adb:` (remote/physical)** — apkeep runs ON THE HOST; the APK is pushed to
  the endpoint via goadb (or `adb -H <host> -P <port>` for the apkeep-download
  path). The host needs `android-tools` (adb) + apkeep for the `package:` path
  (PKGBUILD optdepends; apkeep ships as an upstream binary — no Arch package);
  the committed-`apk:` path needs neither (pure goadb push).

**Build-vs-runtime boundary (load-bearing).** The Android system image + API
level are baked into the referenced `candy:` image at BUILD time (sdkmanager in
the android-sdk layer). `kind: android` REFERENCES that image — it never drives
a build. `device:`/`api_level:` are documentation, not assertions or build
drivers. Two API levels = two images, each with its own `kind: android`.

## `apk:` — the package format (declared in layers)

```yaml
# candy/my-android-apps/charly.yml — name-first: the candy name is the top-level key,
# the apk: list is inline in the candy body
my-android-apps:
    candy:
        version: 2026.145.1700
        apk:
            - package: org.fdroid.fdroid   # apkeep download by id
              source: apk-pure             # apk-pure(default) | google-play | f-droid | huawei-app-gallery
              arch: x86_64                 # native ABI (apk-pure) — match the emulator
            - apk: tests/data/MyApp.apk    # committed local APK (project-root- or layer-relative), goadb push
```

Each entry is **`package:` (apkeep) XOR `apk:` (committed file)**. `source:`
applies only to `package:`. The format compiles to an `ApkInstallStep` that
ONLY `target: android` executes — at image build and on
local/vm/pod/k8s targets it is recorded-skipped (there is no Android device
there; this is the same "wrong-venue skip" `aur:` uses off-Arch). A layer
carrying only `apk:` is valid install content.

Compared to a sideloaded APK: apps with a static-library dependency (e.g.
Chrome's Trichrome) can't be sideloaded — install those via the Play Store
image (preinstalled) instead.

## `target: android` deploy

```yaml
# charly.yml — the device deploys INTO the emulator pod (pod → android), so it is a
# resource node placed UNDER the android-stack deploy
android-stack:
    pod:
        image: android-emulator
    device:                              # deploy-into member: applies apk: layers onto the device
        android:
            from: pixel9a-36             # → the kind: android device, deployed onto the emulator pod
            add_candy:                   # deploy data inline in the substrate value
                - my-android-apps        # layers whose apk: packages install onto the device
```

`charly bundle add android-stack.device` resolves the device, gates on
`sys.boot_completed`, and installs the `add_candy:` candies' `apk:` packages via
the **external `deploy:android` substrate** (F1 — served out-of-process by
candy/plugin-adb). Apps ride in on `add_candy:` (the same overlay mechanism
local/vm targets use) — there is no separate apk-list field. `charly bundle del`
best-effort `pm uninstall`s each `package:` id (replayed from the deploy's
recorded reverse ops; the device/pod lifecycle is owned by the pod deploy).

A top-level (non-nested) `target: android` deploy works too — for an `image:`
device it resolves the running container by image name; for an `adb:` device it
talks straight to the endpoint.

## Nested deployment (`pod → android`)

Mirrors `vm → k8s`. The emulator runs in a pod; the device deploys onto it; the
apps deploy onto the device. `target: android` is a **passthrough** hop in the
deploy chain (the device shares its host pod's adb venue / the endpoint addr —
there is no shell venue to "enter"), so `charly check live pod.android` runs the
device's checks against the pod's published adb port. A pod's children can only
deploy AFTER `charly start` (the container doesn't exist at `charly bundle add` time),
so `charly bundle add --node-only` brings the pod up first and the children deploy
afterwards by dotted path; `charly check run <bed>` automates this (deploy pod →
config → start → deploy nested children → check-live).

## One installer + one plugin (R3 / F1)

candy/plugin-adb owns ALL Android device interaction — the `adb:` check verb,
the `deploy:android` substrate, AND the goadb-backed `charly status` probe — so
the goadb dependency + the single apk install path (`install.go`:
`installByPackage` apkeep+adb / `installFromHostApk` goadb push / `uninstall`)
live in ONE plugin, never duplicated across verb and deploy.

**F6/FINAL-K5-unit-6a moved the preresolve leg wholesale INTO the plugin** —
the deploy is no longer split host ⇄ plugin for its preresolve DATA (only the
two genuinely LoadUnified/credential-store-coupled touches still reach the
host, over the generic seam below):

- **Plugin** (`candy/plugin-adb/preresolve.go`, the `deploy:android`
  preresolve leg) resolves the device endpoint (engine inspect /
  `${HOST_PORT:N}` / google-play creds from the credential store) and collects
  the apk install specs from the deploy's compiled plans (committed-APK paths
  → absolute host paths) itself, reaching the host ONLY via the generic
  `"deploy-entity-resolve"` HostBuild seam for the deploy-tree node + the
  `kind:android` entity/credentials, and ships the result as
  `DeployVenue.Substrate` (a `spec.AndroidDeployVenue`).
- **Plugin** (`candy/plugin-adb/deploy.go`, the `deploy:android` provider) gates
  on `sys.boot_completed`, installs each app with retry (reusing the SAME
  `install`/`install-app` method handlers the `adb:` verb dispatches), and returns
  the `pm uninstall` teardown ops the host records + replays at `charly bundle del`.

So the apk format, the check verbs, and the deploy substrate can never drift on
single/split/`.xapk` handling — they all flow through the one provider.

## R10 bed

`check-android-emulator-pod` nests two devices: `device` (in-pod, installs
F-Droid via apkeep) and `device-net` (the same emulator addressed as a remote
adb ENDPOINT, installs the committed ApiDemos via goadb) — proving both device
kinds with no physical hardware. The android-emulator-layer check ASSERTS the
results (`apk-fdroid-present`/`-launch`, `apk-net-apidemos-present`).

## Implementation map

`target: android` is an EXTERNAL deploy substrate (F1): it resolves to
`pluginDeployTarget` (`charly/unified_targets.go`, S3b), dispatched via
`candy/plugin-bundle`'s `Invoke(OpDeployDispatch)` to the substrate's own
`InvokeProvider`, served by candy/plugin-adb. There is no in-proc android
deploy target.

**F6/FINAL-K5-unit-6a moved the ENTIRE preresolve leg plugin-side** — every
host-core file that used to own it (`charly/android_spec.go`,
`charly/android_deploy_cmd.go`, `charly/android_deploy_preresolve.go`, and the
general per-substrate preresolver hook registry `charly/deploy_preresolve.go`)
is DELETED. `candy/plugin-adb/preresolve.go` now owns it end-to-end (mirroring
`candy/plugin-kube/preresolve.go`'s `deploy:k8s` move): it resolves the device
endpoint (engine inspect / `${HOST_PORT:N}` / google-play creds) and collects
the apk install specs itself, reaching the host ONLY for the two genuinely
LoadUnified/credential-store-coupled touches (resolving the deploy-tree node,
and the `kind:android` entity + its google-play credentials) via the GENERIC
`"deploy-entity-resolve"` HostBuild seam — everything else (engine-inspect,
port resolution, the committed-APK path walk) is pure/portable and runs
plugin-side directly, returning a `spec.AndroidDeployVenue`.

- `candy/plugin-adb/preresolve.go` — the `deploy:android` PRERESOLVE leg:
  `AndroidSpec`/`AndroidAdbEndpoint`/`AndroidGoogleAccount`/`ApkPackageSpec`,
  device-endpoint resolution, and the apk install-spec collection all live
  here now (relocated wholesale from the DELETED `charly/android_spec.go` +
  `android_deploy_cmd.go` + `android_deploy_preresolve.go`).
- `charly/provider_deploy.go` — `externalizedDeploySubstrates` (the F1 source of
  truth) + the relaxed `checkDeployProviderBijection` (in-proc XOR externalized).
- `charly/plugin_prescan.go` — `isExternalDeploySubstrate` (a substrate kind is
  external iff in `externalizedDeploySubstrates`).
- `sdk/spec/deploy_wire.go` — `DeployVenue.Substrate` + `AndroidDeployVenue`.
- `candy/plugin-adb/deploy.go` — the `deploy:android` provider (boot gate + install
  loop with retry + uninstall reverse ops); `install.go` — the shared installer.
- `deploykit.ApkInstallStep` (`sdk/deploykit/steps.go`); `sdk/deploykit/install_build.go` —
  `compileApkStep` (the plugin-side preresolver reads this step; no DeployTarget executes it).
- `charly/unified.go` — loader wiring (mirrors every `k8s` site).
- `charly/deploy.go` `BundleNode.Android`; `charly/bundle_add_cmd.go` dispatch +
  `--node-only`; `sdk/deploykit/deploy_chain.go` / `charly/deploy_tree.go` passthrough.

## Related skills

- `/charly-check:adb` — low-level device control (the verbs the installer shares).
- `/charly-check:appium` — UI automation against the device.
- `/charly-core:deploy` — `target: android` is one of the deploy targets.
- `/charly-image:layer` — the `apk:` field is part of the layer schema.
- `/charly-internals:install-plan` — the IR `ApkInstallStep` plugs into.
- `/charly-kubernetes:kubernetes` — the `kind: k8s` pattern `kind: android` mirrors.

## When to Use This Skill

**MUST be invoked** for any task involving `kind: android`, `target: android`
(the external `deploy:android` substrate), the `apk:` layer package format, an
adb-endpoint device, or nested `pod → android` deployment. Invoke BEFORE reading the android_*.go
source or editing a device's `charly.yml` / a layer's `apk:` list.
