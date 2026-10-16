# Flux layers

The FluxInstance in `flux/clusters/home/flux-system/` syncs `flux/clusters/home`
from `main`. Every numbered directory under `flux/` has one Kustomization there,
with `prune: true`, `wait: true` and ordering only through `dependsOn`:

| Kustomization | Path | Depends on |
| --- | --- | --- |
| `sealed-secrets` | `flux/10_sealed-secrets` | - |
| `controllers` | `flux/20_controllers` | `sealed-secrets` |
| `config` | `flux/30_config` | `controllers` |
| `openbao` | `flux/30_openbao` | `controllers` |
| `services` | `flux/40_services` | `config`, `openbao` |
| `apps` | `flux/50_apps` | `services` |
| `netbird-operator` | `flux/60_netbird-operator` | `apps` |
| `access` | `flux/70_access` | `netbird-operator` |

## Rules

- Only the directory carries the number. Kustomization names are never renamed:
  a renamed Kustomization is a new object, and the old one prunes everything it
  applied.
- A secret never sits in a layer that depends on the layer consuming it.
- `netbird-operator` comes after `apps` because its API key is only available
  once NetBird runs. Everything that needs the operator's CRDs (ClusterProxy,
  SetupKey, SidecarProfile) lives in `access`.
- `access` reads `SetupKey` health from its `Ready` condition only: netbird-operator
  0.8.0 never advances `status.observedGeneration` after the first reconcile, so the
  default health check would wait forever.
- Layer directories have no `kustomization.yaml`; Flux generates one from every
  manifest below the path. A subdirectory that needs a generator
  (`20_controllers/snapshot-controller`) carries its own.
