---
name: pod
description: Schema reference for `kind: pod` and deploy entities — charly.yml entry shape, tree-position nesting, sidecars, pod networking. For verb-level operations see /charly-core:deploy.
---

# `kind: pod` and deploy entities — Schema Reference

This skill is a thin schema pointer. For runtime verbs (`charly bundle add`, `charly bundle del`, `charly update`), see `/charly-core:deploy`.

## What lives in `kind: pod` / a deploy node

A `pod` entity declares a co-scheduled set of containers and the volumes / network / sidecars they share. A deploy node is the **bind site** — its first child key is the substrate kind at the EDGE (`pod:` the default, or `vm:` / `k8s:` / `local:` / `android:`, or `group:` for a targetless member group), carrying `image:` (the box a `pod`/`k8s`/`android` runs) or `from:` (inherit a same-kind template), plus the runtime knobs (encrypted volumes, tunnels, env, ports).

A host/remote deploy MUST use the `host:` FIELD on a `local:` (or `pod:`) deploy (`local: {from: <template>, host: <user@machine>}`) — there is NO `host:` venue KIND. `group:` here is the targetless deploy group — a set of member resources with no own workload.

Schema sources (read these for the canonical truth):

- `charly/deploy.go` — `BundleConfig` + `BundleNode` Go types, the deploy entry shape, target discriminator.
- `sdk/spec/cue_types_gen.go` (generated) — the `PodSpec` Go type / `kind: pod` shape.
- `/charly-core:deploy` — the verb-level skill covering `charly bundle add` / `charly bundle del` / `charly update`.

## Nesting & membership (tree position)

Nesting is expressed by **tree position**, not a `nested:` field: a resource node placed UNDER another resource node deploys INTO it (the migrated `nested:` — e.g. a `pod → android` tree), and the parent and its nested entries share the pod and the tunnel; each nested entry is a separate quadlet/process inside the same pod namespace. A resource node placed directly under a deploy is instead a sibling member (the migrated `peer:`). There are no authored `nested:` / `peer:` / `target:` / `on:` fields — membership is read from the tree.

## Sidecars

`sidecar:` declares co-running containers with their own env-var routing (`env_accept` / `env_require`). See `/charly-automation:sidecar` for the topic skill.

## Cross-references

- Verb-level: `/charly-core:deploy`, `/charly-core:charly-update`, `/charly-core:remove`.
- Sibling kinds: `/charly-image:image`, `/charly-vm:vm`, `/charly-kubernetes:kubernetes`, `/charly-local:local-spec`.
- Topics: `/charly-automation:sidecar`, `/charly-automation:enc`.
