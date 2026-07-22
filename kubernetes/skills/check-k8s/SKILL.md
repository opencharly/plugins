---
name: check-k8s
description: Kubernetes cluster-probe declarative check verb — the `kube:` check verb (nodes, pods, ingress, storage class, addon health, apply/delete, and arbitrary resource GETs) served out-of-process by the candy/plugin-kube plugin (vendored client-go; no external kubectl required).
---

MUST be invoked before any work involving: the declarative `kube:` check
verb, cluster-readiness probes from a candy/box plan, ingress / storage
class assertions, k3s default-addon health checks, or authoring `kube:`
steps in a candy/box plan (the candy's `plan:` list) in charly.yml.

**There is no host `charly check kube` command.** `kube` is a DECLARATIVE
check verb only: it is authored as a `kube: <method>` inline Op in a candy/box
plan `check:` step and dispatched through the provider registry to the
out-of-process `candy/plugin-kube` module — the same way the bed's checks run
under `charly check live` / `charly check run`. The Kubernetes
cluster-probe implementation (and the `k8s.io/client-go` +
`k8s.io/apimachinery` dependency) lives entirely in that external plugin, NOT
in charly's core. This mirrors the `adb:` and `appium:` verbs (see
charly/check_cmd.go).

The cluster-probe verb is spelled `kube`; the `k8s` spelling is reserved for
the deploy KIND only (`kind: k8s`, `--target k8s`, a `k8s:` entity or
cross-ref).

## Method surface

Every method below is the `kube:` map's `method:` (or the scalar value for a bare
method). The Modifiers column names the kube-exclusive fields that live INSIDE the
`kube:` map — EXCEPT `timeout:`, which is a shared `#Op` sibling of the `kube:` key.
A `kube:` step is a `check:` step.

| `kube:` value | Modifiers | Output |
|---|---|---|
| `nodes` | — | `<name> <Ready\|NotReady>` per line |
| `wait-nodes` | `kube_count:` (N), `name:` (host), `timeout:` (120s) | block until N (or the named) node is Ready |
| `pods` | `namespace:`, `label:` (selector) | `<ns>/<name> <phase>` per line |
| `wait-ready` | `kube_kind:` (K), `name:` (N), `namespace:`, `timeout:` (120s) | block until the resource is Ready |
| `ingress` | `namespace:` | `<ns>/<name> class=<c> hosts=<h> backends=<b>` |
| `ingressclass` | — | `<name> default=<bool>` |
| `storageclass` | — | `<name> default=<bool>` |
| `service` | `namespace:` | `<ns>/<name> <type> <clusterIP> <externalIP>` |
| `lb-external-ip` | `namespace:`, `name:` (svc), `timeout:` (60s) | print the assigned external IP |
| `addons` | `namespace:` (kube-system), `timeout:` (180s) | roll-up: Traefik + ServiceLB + local-path all Ready |
| `apply` | `manifest:` (path), `namespace:` | apply multi-doc YAML via the dynamic client |
| `delete` | `manifest:` (path), `namespace:` | delete the resources named in the manifest |
| `raw` | `kube_resource:` (plural), `kube_group:`, `kube_version:` (v1), `name:`, `namespace:` | GET an arbitrary resource as JSON |

The full kube-map field set: `name:`, `namespace:`, `label:`, `cluster:`,
`kubeconfig:`, `kube_context:`, `kube_kind:`, `kube_count:`, `manifest:`,
`kube_resource:`, `kube_group:`, `kube_version:`, `json:` (all inside the `kube:`
map). The only shared `#Op` sibling a `kube:` step commonly carries is `timeout:`.

## Cluster selection

Every method accepts the same three cluster-selection modifiers. The plugin
resolves the `cluster:` profile to a concrete kubeconfig context via the generic
`cc.ResolveClusterContext` reverse-leg; the precedence is:

1. `kubeconfig: <path>` — direct kubeconfig file pointer. Overrides
   everything.
2. `cluster: <name>` — a `kind: k8s` cluster template name. The host
   resolves it via `findK8sSpec` (the project `charly.yml` / `k8s.yml`
   loader) to the template's `kubeconfig_context:`, which selects the
   context; the kubeconfig path defaults to `$KUBECONFIG` then
   `~/.kube/config`.
3. `kube_context: <name>` — override the kubeconfig context directly.
4. None given → current-context of the default kubeconfig (matches
   `kubectl` with no flags).

`charly bundle add vm:k3s-srv` (or any deploy whose layers include
`k3s-server`) provisions a cluster whose kubeconfig is merged into the
default kubeconfig under a context named after the deploy (the plugin-side
`k3s-post-provision` finalization dispatched by `K3sPostProvision` via
`invokeKubePluginWithBroker`, which retrieves the kubeconfig, rewrites its
guest-forwarded server, and merges it via `mergeKubeconfig` — all inside
`candy/plugin-kube`), so a plan step can then address it with `cluster: k3s-srv`:

```yaml
- check: every node reports Ready
  kube:
    method: nodes
    cluster: k3s-srv
  stdout: {contains: "Ready"}
  context: [deploy]
```

## Declarative `kube:` steps in a candy's plan

The verb is authored from a candy's plan steps via the `kube:`
discriminator on a step's `Op`. In the unified node-form the plan IS a `plan:`
list — each step is an ordered list item under the candy's `plan:` (named by its
optional `id:`). Every method above maps to a method name; its kube-exclusive
fields (`name:`, `namespace:`, `cluster:`, `kubeconfig:`, `kube_kind:`,
`kube_count:`, `manifest:`, `kube_resource:`, `kube_group:`, `kube_version:`) go
INSIDE the `kube:` map, while `timeout:` stays a sibling. A `kube:` step is a
`check:` step.

Example from `candy/k3s-server/charly.yml` — the k8s cluster-readiness steps as
list items under the `k3s-server:` candy's `plan:`:

```yaml
k3s-server:
  candy:
    version: …
    description: …
    # … require / distro / service elided …
    plan:
      # … earlier build-context steps elided …
      - check: the cluster reports at least one Ready node
        kube:
          method: wait-nodes
          cluster: "${DEPLOY_NAME}"
          kube_count: 1
        timeout: 180s
        stdout: {contains: "Ready"}
        context: [deploy]
      # `addons` BLOCKS until Traefik + ServiceLB + local-path are all Ready, so it
      # MUST precede any ingressclass/storageclass step — those resources are
      # registered by the addon stack. Ordering matters: `ingressclass`/`storageclass`
      # are one-shot list verbs with no internal wait, and they exit 0 on an EMPTY
      # list, so a `contains` matcher run before the addons settle FAILS rather than
      # waits. Gate first, assert second.
      - check: Traefik, ServiceLB, and local-path addons are all Ready
        kube:
          method: addons
          cluster: "${DEPLOY_NAME}"
        timeout: 240s
        context: [deploy]
      - check: Traefik is registered as the cluster's default ingress class
        kube:
          method: ingressclass
          cluster: "${DEPLOY_NAME}"
        stdout: {contains: "traefik"}
        context: [deploy]
```

`cluster: "${DEPLOY_NAME}"` lets a candy's `context: [deploy]` step address its own
cluster generically: `${DEPLOY_NAME}` is a **runtime-only check var** resolving to
the sanitized deploy name (`:`/`.`/`/` → `-`) — the SAME identifier
`K3sPostProvision` uses for the kubeconfig context + ClusterProfile. It is
UPPERCASE because the check-var expander only recognizes uppercase names; a
lowercase `${deploy_name}` (the artifact-path token) is NOT an check var and is
rejected by `charly box validate` in kube identifier fields.

`wait-nodes` with `name:` set matches a single specific node (used by
`k3s-agent`'s join-confirmation test). Without `name:`, it waits until
`kube_count:` nodes are Ready.

## Method notes

- **apply / delete** — limited to the kinds in `kindToPluralResource()`
  (in the plugin's `cluster.go`). Static table by design; adding a new
  kind is a one-line addition, avoiding the RESTMapper discovery bloat.
  Documents without a namespace inherit `namespace:`.
- **raw** — escape hatch for any resource not covered by the named
  methods. `kube: {method: raw, kube_resource: nodes}` lists nodes;
  `kube: {method: raw, kube_resource: configmaps, namespace: kube-system,
  name: foo}` prints one ConfigMap as JSON.
- **addons** — assumes the stock k3s addon stack (Traefik, ServiceLB,
  local-path-provisioner) in `kube-system`. Explicit `disable:` in a
  k3s-server layer will cause this method to fail — the failure is
  intentional since the test speaks to "default k3s stack healthy".
- **lb-external-ip** — polls `.status.loadBalancer.ingress[].ip` /
  `[].hostname` until one appears; for k3s this is ServiceLB
  (klipper-lb) advertising the host's node IP.

## Implementation

The verb is dispatched out-of-process; the client-go stack does not link into
charly's core binary.

- `candy/plugin-kube` — the out-of-tree plugin module that owns the verb and
  the entire `k8s.io/client-go` + `k8s.io/apimachinery` dependency:
  - `provider.go` — the Provider that advertises the `kube` verb; the
    registry routes a `kube:` step to it (`ResolveVerb("kube")` → its
    `grpcProvider` → `invokeVerbProvider` hands it the full `#Op` as
    `params_json`).
  - `cluster.go` — builds the `rest.Config` from kubeconfig + context (the
    dynamic client via `k8s.io/client-go/dynamic` + `unstructured` walkers,
    no typed clientset) and `kindToPluralResource()` for apply/delete.
  - `methods.go` — the `dispatch()` method router + the 13 method
    implementations (`runNodes`, `runWaitNodes`, `runApply`, …).
  - `merge.go` — `mergeKubeconfig`: the clientcmd merge that folds a retrieved
    k3s kubeconfig into the operator's `~/.kube/config` under a named context
    (so the `k8s.io/client-go/tools/clientcmd` dependency lives here too, not
    in core). Called DIRECTLY by this same plugin's `k3s_post.go`
    (`k3sPostProvision`) — no separate host-orchestrated merge round-trip.
  - `k3s_post.go` — the WHOLE k3s post-provision finalization (S3, FINAL/K5
    unit 6, relocated wholesale from the now-thin `charly/k3s_post.go`):
    `k3sPostProvision` checks the retrieved-kubeconfig path, rewrites its
    GUEST-local server URL to the HOST-forwarded port (via the generic
    "deploy-entity-resolve" HostBuild seam, for the LoadUnified-coupled VM
    port-forward lookup), then calls `mergeKubeconfig` directly.
  - `schema/kube.cue` — the plugin's served CUE schema: the `#KubeInput` def
    carries the method enum + every kube modifier, served over the Describe
    channel and spliced onto the base for validation. Authoring is unchanged
    (`kube: nodes`, not `plugin: kube`); the internal plugin/plugin_input wire
    envelope the sugar desugars to is never authored.
- `charly/k8s_plugin.go` — `invokeKubePluginWithBroker`: the core seam that
  builds a synthetic `kube:` `#Op` and dispatches it to the plugin WITH the
  reverse-channel broker (`InvokeWithExecutor`) through the registry — the
  broker access is needed for the plugin's own "deploy-entity-resolve"
  HostBuild leg. Used by the k3s deploy path to invoke the
  `k3s-post-provision` method.
- `charly/k3s_post.go` — now a ONE-CALL dispatch shim: `K3sPostProvision`
  marshals `{method: "k3s-post-provision", artifact_key, deploy_name}` and
  calls `invokeKubePluginWithBroker`, printing the plugin's returned status
  line. The retrieve-check, port-forward rewrite, and merge all run INSIDE
  `candy/plugin-kube` now (see `k3s_post.go` above). No client-go import
  remains in core.
- `charly/k8s_config.go` — `findK8sSpec` looks up a `K8sSpec` (`kind: k8s`
  cluster template) by name from the project `charly.yml` / `k8s.yml`, and
  `resolveClusterContext` (the host side of the `cc.ResolveClusterContext`
  reverse-leg) uses it to turn a `kube:` step's `cluster:` profile name into a
  concrete kubeconfig context — the out-of-process plugin PULLS the mapping (it
  cannot reach the project loader itself).

There is no `charly/k8s_cmd.go`, `kubeMethods` table, `runKube` dispatcher,
`posKube*` flag builder, or `k8sClusterFlags`/`LoadClusterProfile` symbol —
all were removed when the verb was externalized.

## Related skills

- `/charly-check:check` — the unified `charly check` surface (image / live /
  run), the plan-step vocabulary, and how the provider registry dispatches
  declarative verbs.
- `/charly-kubernetes:kubernetes` — deploying images to a K8s cluster
  (`kind: k8s` cluster templates, Kustomize generation, `charly bundle`).
- `/charly-internals:plugin` — the Provider model and the out-of-process
  plugin dispatch the `kube:` verb rides on.
- `/charly-infrastructure:k3s` — the k3s-server / k3s-agent candies whose
  plans author these `kube:` readiness steps.
