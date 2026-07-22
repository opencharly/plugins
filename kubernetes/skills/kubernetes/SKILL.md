---
name: kubernetes
description: |
  MUST be invoked before any work involving: `charly bundle add --target kubernetes`, `charly bundle from-box`, Kustomize manifest generation, cluster profiles, K8s deployments, `kubernetes:` block in deploy spec, or OCI-label capabilities.
---

# Kubernetes — Deploying OpenCharly Images to K8s Clusters

## Overview

OpenCharly can deploy built images to a Kubernetes cluster by emitting a Kustomize `base/` + `overlays/` tree. The deployment schema stays **target-agnostic** — the deploy node describes *what the workload needs* (kind, replica, resources, exposure, storage, probes); a per-cluster **`kind: k8s` cluster template** (the `k8s:` entity, which absorbed the former cluster-profile file) supplies the K8s-specific knobs (storage class, ingress class, cert issuer, secret backend).

Every box runtime contract is baked into OCI labels at build time, so **a K8s deploy is possible without access to `charly.yml`** — the `charly bundle from-box` verb reads capabilities from the pushed image alone.

## Quick reference

| Action | Command | Description |
|---|---|---|
| Add K8s deploy | `charly bundle add <name> <ref> --target kubernetes` | Read BoxConfig + the deploy node + the `kind: k8s` cluster template; emit `.opencharly/k8s/<name>/` Kustomize tree |
| Source-less deploy | `charly bundle from-box <registry/name:tag> [name] --cluster <name>` | Deploy from OCI labels only — no `charly.yml` needed (see Part F.10) |
| Sync to cluster | `charly bundle sync <name>` | `kubectl apply -k .opencharly/k8s/<name>/overlays/default` |
| Show generated manifests | `charly bundle show <name>` | `kubectl kustomize …` — see what would apply |
| Delete K8s deploy | `charly bundle del <name>` | Remove overlay dir; base stays if other instances reference it |

## The three-layer model

| Concern | Schema slot | OCI label home |
|---|---|---|
| **Build** — what goes INTO the image | `box.build:` (or legacy `BoxConfig`) | no (consumed at build) |
| **Capabilities** — box runtime contract | `box.capabilities:` (or layer rollups) | **yes** — every field under `ai.opencharly.*` |
| **Deployment** — how to run the image | a name-first deploy node (substrate kind at the edge — here `k8s:`) in `charly.yml` + `~/.config/charly/charly.yml` overlay | no |

The completeness invariant: every exported field on `BoxMetadata`/`Capabilities` has a `CapabilityLabelMap` entry. A compile-time test enforces this — a new capability field without a label mapping fails the build. See `charly/capabilities.go`.

## Deployment schema — target-agnostic fields

A K8s deployment is a name-first `k8s:` deploy: the `k8s:` value carries the
scalars + the cross-refs (`image:` = the box to deploy, `from:` = the `kind: k8s`
cluster template) AND every non-scalar field (resources / security / expose /
storage / probes / the `kubernetes:` deploy-knobs block) — all inline in the `k8s:`
value.

```yaml
openclaw:
  k8s:
    image: openclaw                 # the box to deploy (falls back to the deploy name)
    from: production                # cross-ref → inherit the kind:k8s cluster template
    kind: service                   # service | daemon | batch | scheduled | oneshot
    replica: 3
    restart: always                 # always | on-failure | never (honored on Pod/Job/CronJob)
    resources:
      cpu_request: "500m"
      memory_request: 512Mi
    security:
      memory_max: 2Gi               # → resources.limits.memory
      cpus: "1.5"                   # → resources.limits.cpu
    expose:
      host: openclaw.example.com
      path: /
      tls: true                     # → cert-manager annotation from the cluster template
    storage:
      - {name: data, size: 20Gi, class_hint: fast, access: single-writer}
    probes:
      liveness:  {http: {path: /healthz, port: 8080}}
      readiness: {http: {path: /ready,   port: 8080}}
    kubernetes:
      namespace: apps               # optional override of the cluster template default
      patches: []                   # escape hatch: strategic / JSON6902 patches
      raw: []                       # escape hatch: paths to raw manifests included verbatim
```

**Workload kind heuristic** (inside `charly/k8s_generate.go`):

```
kind: service   + storage: []       → Deployment
kind: service   + storage: [...]    → StatefulSet  (auto volumeClaimTemplates)
kind: daemon                        → DaemonSet
kind: batch                         → Job
kind: scheduled (+schedule:)        → CronJob
kind: oneshot                       → Pod
```

Explicit override: `kubernetes.workload: Deployment` (rare — prefer `kind:`).

## Cluster template (`kind: k8s`)

One `kind: k8s` entity per cluster, declared name-first in `charly.yml` (or a discovered `k8s.yml`). The `k8s:` kind **absorbed the former `kind: cluster-profile` file** — `charly migrate` synthesizes a `kind: k8s` entry from any pre-existing `clusters/<name>.yaml`. It is the **only** place cluster-specific K8s knobs live; a deploy reaches it by name through its `from:` cross-ref. The `k8s:` value carries the scalars (`box:` cross-ref, `kubeconfig_context:`, `admission_policy:`, `default_namespace:`) AND every non-scalar policy block (storage / ingress / secret / image_default / pod_default / defaults) — all inline in the `k8s:` value.

```yaml
production:                          # a kind: k8s cluster template (name-first)
  k8s:
    box: ""                          # empty → a cluster-policy-only template (the workload box is named on the deploy)
    kubeconfig_context: gke_prod_us-east1
    admission_policy: restricted     # restricted | baseline | privileged
    default_namespace: apps
    storage:
      class_default: fast-ssd-retain
      class_fast: fast-ssd
      class_cheap: hdd-delete
      class_encrypted: fast-ssd-luks
      access_mode_default: ReadWriteOnce
    ingress:
      enabled: true
      class: nginx
      cert_issuer: letsencrypt-prod  # cert-manager ClusterIssuer
      path_type_default: Prefix
    secret:
      backend: external-secrets      # external-secrets | sealed-secrets | raw
      store: vault-prod
      prefix: prod/
    image_default:
      pull_policy: IfNotPresent
      pull_secrets: [regcred-prod]
    pod_default:
      priority_class: standard
      tolerations: []
      node_selector: {}
    defaults:
      labels: {managed-by: opencharly}
```

New cluster = write a new `kind: k8s` template; zero deploy changes.

## Generator output

```
.opencharly/k8s/<deployment-name>/
├── base/
│   ├── kustomization.yaml           # commonLabels, resources: […]
│   ├── deployment.yaml              # or statefulset.yaml / daemonset.yaml / job.yaml / cronjob.yaml / pod.yaml
│   ├── service.yaml
│   ├── pvc-<name>.yaml              # per storage entry (Deployment/DaemonSet); StatefulSet uses volumeClaimTemplates
│   ├── ingress.yaml                 # when expose.host set AND the k8s template's ingress.enabled
│   └── raw/                         # copied from kubernetes.raw:
└── overlays/
    └── <instance>/                  # "default" for bare name; "prod" for image/prod
        └── kustomization.yaml       # namespace override + patches from kubernetes.patches:
```

Apply: `kubectl apply -k .opencharly/k8s/<name>/overlays/<instance>` (or `charly bundle sync <name>`).

**Egress validation.** Every manifest is validated through `writeK8sYAML` before it
is written: workload / service / pvc / ingress against the `#K8sObject` envelope
(non-empty `apiVersion`/`kind` + named `metadata`), and the base + overlay
`kustomization.yaml` against `#Kustomization`. A structurally-broken manifest fails
deploy generation instead of reaching the cluster. Owned by `/charly-internals:egress`.

## Source-less deploy — `charly bundle from-box`

Proves the self-contained image invariant: a deploy pipeline with **no access to `charly.yml`** can still produce a correct Kustomize tree.

```bash
# On a machine that doesn't have the source repo:
charly bundle from-box quay.io/myorg/openclaw:v2 openclaw \
    --target kubernetes --cluster production --namespace apps
# Reads: OCI labels (capabilities) + the `production` kind:k8s cluster template
#        + ~/.config/charly/charly.yml (if present, for per-machine overrides)
# Emits: .opencharly/k8s/openclaw/base/ + overlays/default/
charly bundle sync openclaw                   # kubectl apply -k ...
```

## Relevant code

- `charly/k8s_config.go` — `K8sDeployConfig` (the deploy's `kubernetes:` deploy-knobs block: namespace / workload override / patches / raw)
- `sdk/spec/cue_types_gen.go` (generated) — `K8sSpec` (the `kind: k8s` cluster template; absorbed the former `ClusterProfile` / `clusters/*.yaml`)
- `candy/plugin-kube/preresolve.go` — the PLUGIN-side `deploy:k8s` preresolver (F6/FINAL-K5-unit-6a, relocated from the DELETED `charly/k8s_deploy_preresolve.go`). `target: k8s` is an EXTERNAL deploy substrate (F1): it resolves out-of-process to candy/plugin-kube's `deploy:k8s` provider (beside its `kube:` verb), NOT a compiled-in DeployTarget. The preresolver resolves the image Capabilities + the `kind: k8s` cluster template (the LoadUnified-coupled lookup reaching the host via the "deploy-entity-resolve" seam), runs `GenerateK8sKustomize` via the host's `host_build_k8s_generate.go` "k8s-generate-kustomize" HostBuild seam, and ships the egress-validated overlay path in `DeployVenue.Substrate`; the plugin runs `kubectl --context <ctx> apply -k`. The user-facing surface (schema, cluster templates, Kustomize output) is unchanged. See `/charly-internals:install-plan` + `/charly-internals:plugin`.
- `charly/k8s_generate.go` — `GenerateK8sKustomize` is now a thin in-core SHIM (M13) that Invokes the compiled-in `candy/plugin-k8sgen` (`verb:k8sgen`/`OpEmit`) for the manifest docs, validates each host-side via the M16 egress shim, and writes the tree; consumed by the plugin-side preresolver (via `host_build_k8s_generate.go`) AND `charly bundle from-box --target k8s` (calling it directly). The generator lives in `candy/plugin-k8sgen/k8sgen.go`
- `candy/plugin-k8sgen/` — the compiled-in Kustomize GENERATOR candy (M13): `k8sgen.go` (the ported workload/service/pvc/ingress/kustomization builders + the workload-kind heuristic + `GenerateTree`), serving `verb:k8sgen`/`OpEmit` over `spec.K8sGenInput` → `spec.K8sGenReply` manifest docs; no client-go (split from the heavy external plugin-kube so it resolves in the project-less from-box path)
- `charly/bundle_from_box_cmd.go` — `BundleFromBoxCmd` (`charly bundle from-box`, K8s among its targets)
- `charly/capabilities.go` — `Capabilities` (alias of `BoxMetadata`) + `CapabilityLabelMap` + completeness check

## Related skills

- `/charly-core:deploy` — unified `charly bundle add`/`del` verb; K8s is one of three targets
- `/charly-internals:capabilities` — OCI label contract the K8s generator reads from
- `/charly-internals:install-plan` — shared IR across build + deploy targets
- `/charly-internals:egress` — the CUE egress gate that validates every generated manifest before write (`#K8sObject` / `#Kustomization`)
