---
name: k3s-agent
description: |
  k3s worker (agent) node — joins an existing k3s-server via pre-shared token.
  Fully declarative: same charly secrets set once + env K3S_SERVER_URL per agent deploy.
---

# k3s-agent -- k3s worker node

## Candy Properties

| Property | Value |
|----------|-------|
| Install files | `charly.yml`, `task:`, `service:`, `secret_require:`, `env_require:` |
| Depends on | `/charly-infrastructure:k3s` |
| Service | `k3s-agent.service` (system scope, enabled) |

## What this candy does

1. Reads `K3S_CLUSTER_TOKEN` from the credential store (same secret the
   server consumes — auto-generated on the first server-or-agent
   deploy via `ensureCandySecret`; subsequent deploys read the
   persisted value, so agents and server automatically share the
   token without operator setup).
2. Requires `K3S_SERVER_URL` from charly.yml env (e.g.,
   `https://k3s-srv.lan:6443`).
3. Writes `/etc/rancher/k3s/config.yaml` with `server:` and `token:`.
4. Emits `/etc/systemd/system/k3s-agent.service` running `k3s agent`.

No join-token handoff, no kubeconfig retricheck — agents only need the
server URL (declarative, known at author time) and the pre-shared token
(from the credential store).

## Usage

```yaml
# charly.yml (assumes k3s-srv already up; see /charly-infrastructure:k3s-server)

# The VM hardware template (a kind: vm entity — name-first node form).
k3s-ag1-vm:
  vm:
    source: { kind: cloud_image, url: "…" }
    ram: 4G
    cpu: 2

# The disposable deploy: overlay the k3s-agent candy into the VM. `from:`
# selects the template; disposable / add_candy / env live on the deploy node.
k3s-ag1:
  vm:
    from: k3s-ag1-vm
    disposable: true
    add_candy: [k3s-agent]
    env:
      K3S_SERVER_URL: https://k3s-srv.lan:6443
      # K3S_CLUSTER must match the cluster profile name registered by the server.
      K3S_CLUSTER: k3s-srv
```

```bash
charly bundle add vm:k3s-ag1
```

The agent registers; a server-side `kube: wait-nodes` check step confirms the
join — the declarative `kube:` verb served out-of-process by `candy/plugin-kube`
(there is no host `charly check kube` command):

```yaml
  confirm-join:
    check: both nodes reach Ready once the agent joins
    kube: wait-nodes
    cluster: k3s-srv
    kube_count: 2
    timeout: 3m
    context: [deploy]
```

## Tests

Build-scope:
- `/etc/rancher/k3s/config.yaml` exists, mode 0600.
- `/etc/systemd/system/k3s-agent.service` exists.

Deploy-scope (uses `/charly-kubernetes:check-k8s`). The cluster-probe verb is
the declarative `kube:` check verb (served out-of-process by `candy/plugin-kube` —
there is no host `charly check kube` command); the `k8s` spelling is reserved for
the deploy KIND only:
- `kube: wait-nodes name=${HOSTNAME}` — this node reaches Ready on the
  server.

## Related Candies
- `/charly-infrastructure:k3s` — Base candy installing the k3s binary (required dep)
- `/charly-infrastructure:k3s-server` — Control-plane node this agent joins
- `/charly-kubernetes:check-k8s` — Test verb used by the agent-joined check
