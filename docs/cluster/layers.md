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

## Contents

| Layer | Holds |
| --- | --- |
| `10_sealed-secrets` | the sealed-secrets controller (`keyrenewperiod: 0`, see [Secrets](secrets.md#sealedsecrets)) |
| `20_controllers` | cert-manager, CloudNativePG and the Barman Cloud plugin, external-secrets, Longhorn, mariadb-operator, the NVIDIA device plugin, the CSI snapshot controller, Traefik |
| `30_config` | ClusterIssuer `letsencrypt-dns` and the wildcard certificate, the CoreDNS database-name rewrites, Longhorn backup target, recurring jobs and `longhorn-single`, the `infra-admin` ServiceAccount |
| `30_openbao` | [OpenBao](openbao.md) |
| `40_services` | [Postgres](../databases/postgres.md), [MariaDB](../databases/mariadb.md), the [frpc tunnel](edge.md#the-tunnel) |
| `50_apps` | the applications listed on the [home page](../index.md#applications) |
| `60_netbird-operator` | netbird-operator and its API key |
| `70_access` | ClusterProxy `home`, the `admins` ClusterRoleBinding, the Ollama SetupKey and SidecarProfile |

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
