# Cluster access

Two ways into the Kubernetes API of `home-server`:

| Path | Who | Context | Serves OpenAPI | Use for |
| --- | --- | --- | --- | --- |
| NetBird ClusterProxy `home` with `.kube/netbird.yaml` | NetBird members of `admins` | `home-netbird` (default) | no | `kubectl` from anywhere on the mesh |
| `https://192.168.1.78:6443` with `.kube/config` from `mint-kubeconfig` | the operator machine on the home LAN | `home` | yes | OpenTofu, Helm |

## The LAN kubeconfig

`mint-kubeconfig` (`nix/packages/mint-kubeconfig.nix`, in the dev shell) writes
`.kube/config` at the repository root:

- server `https://192.168.1.78:6443`, CA from the `kube-system/kube-root-ca.crt`
  ConfigMap;
- user `infra-admin`: a 24-hour token for the ServiceAccount
  `kube-system/infra-admin`, bound to `cluster-admin` in
  `flux/30_config/rbac/infra-admin.yaml`.

```sh
mint-kubeconfig                 # renew from the current .kube/config
mint-kubeconfig path/to/other   # renew from another kubeconfig
```

The source kubeconfig only needs the right to create a token for
`kube-system/infra-admin`. A still-valid `.kube/config` renews itself; once it
has expired, pass any working kubeconfig with that right, such as
`.kube/netbird.yaml` from the mesh. The file is written with mode `0600` and
replaced atomically; `.kube/config` is git-ignored.

The root `.envrc` sets `KUBECONFIG` to `.kube/netbird.yaml:.kube/config`, so
the context `home` from this file is available next to the default
`home-netbird`. The OpenTofu roots that talk to the cluster
(`20_cluster-bootstrap`, `40_databases`, `50_authentik-config`) default
`kubeconfig_path` to this file directly.

## NetBird ClusterProxy

`flux/70_access/cluster-proxy.yaml` declares ClusterProxy `home` in namespace
`netbird`. netbird-operator runs it as a NetBird peer in group
`kubernetes-api`, and the policy `admins-to-kubernetes-api`
(`terraform/60_netbird-config/policies.tf`) lets `admins` reach that group.

The proxy authenticates the NetBird user and forwards to the API server by
impersonation through ServiceAccount `netbird/clusterproxy-home`, whose
ClusterRole may impersonate users, groups, `userextras/*` and `uids`. Kubernetes
authorises the impersonated identity: `flux/70_access/admins-rbac.yaml` binds the
group `admins` to `cluster-admin`.

`.kube/netbird.yaml` is committed and holds only the address
`https://home.netbird-kubeapi-proxy.peers.luuk.internal.` (as printed by
`netbird kubernetes list`), `insecure-skip-tls-verify` and the placeholder
token `none`: the NetBird client and the proxy handle identity. It is the first
file in `KUBECONFIG`, so its `current-context` `home-netbird` is the default;
`bao_jwt_export` mints the OpenBao login token through it (see
[OpenBao](openbao.md#logging-in)). Use `--context home` (Helm:
`--kube-context home`) for the LAN API.

The ClusterProxy path does not serve the OpenAPI document, which Helm and the
OpenTofu `kubernetes`/`helm` providers need; they use the LAN API.
