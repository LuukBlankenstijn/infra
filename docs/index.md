# Home infrastructure

One repository for the home k3s cluster (`home-server`, a single node on the
home LAN at `192.168.1.78`), the public edge VPS, and the OpenTofu roots that
configure what runs on them.

| Directory | Contents |
| --- | --- |
| `flux/` | Everything the cluster runs, reconciled by Flux in numbered layers. See [Flux layers](cluster/layers.md). |
| `terraform/` | OpenTofu roots. The two-digit prefix is the apply order on a fresh setup; equal prefixes are independent. See [Roots](terraform/roots.md). |
| `nix/` | The edge host (`nixosConfigurations.edge`), the dev shell, `mint-kubeconfig` and the docs build. |
| `secrets/` | sops-encrypted bootstrap material needed before OpenBao exists. See [Secrets](cluster/secrets.md). |

## What runs where

| Piece | Page |
| --- | --- |
| Internet → edge VPS → frp tunnel → Traefik | [Edge and public ingress](cluster/edge.md) |
| `kubectl`, Helm and OpenTofu against the cluster | [Cluster access](cluster/access.md) |
| Secret storage and delivery into namespaces | [OpenBao](cluster/openbao.md), [Secrets](cluster/secrets.md) |
| Mesh VPN, login, Kubernetes API over the mesh | [NetBird](cluster/netbird.md) |
| Services published through NetBird | [NetBird reverse proxy](cluster/reverse-proxy.md) |
| Shared database servers | [Postgres](databases/postgres.md), [MariaDB](databases/mariadb.md) |
| What is backed up, where, and how to restore | [Backups](databases/backups.md) |
| Metrics, logs, Grafana, device ingest over mTLS | [Observability](observability/index.md) |

## Applications

Everything in `flux/50_apps`. Hostnames are under `luukblankenstijn.nl`.

| App | Host | State |
| --- | --- | --- |
| Authentik | `auth` | Postgres `authentik` |
| Grafana | `grafana`; device ingest on `logs` and `metrics`, mTLS only | Postgres `grafana`; Loki and Mimir in buckets `luuk-loki`, `luuk-mimir` |
| Grimmory | `grimmory` | MariaDB `grimmory`, Longhorn volumes `data`, `books` |
| Longhorn UI | `longhorn`, behind Authentik forward auth | - |
| Minecraft | Traefik entrypoints `minecraft` (25565/tcp) and `voicechat-udp` (24454/udp) on the node | Longhorn volume |
| NetBird | `netbird` | Postgres `netbird`, `netbird_events`, `netbird_idp`, Longhorn volume `netbird-data` |
| Ollama | no ingress; NetBird sidecar only | Longhorn volume for models |
| Shelfmark | `shelfmark`, behind Authentik forward auth | Longhorn volumes `books`, `config`, `downloads` |
| Traefik dashboard | `traefik`, behind Authentik forward auth | - |
| Vaultwarden | `vaultwarden` | Postgres `vaultwarden`, volume `data` |

Forward auth is the Traefik Middleware `authentik/proxy-auth`; the matching
providers and outpost are configured in Authentik itself, not in OpenTofu. The
IngressRoute `authentik/auth-redirect` sends `/outpost.goauthentik.io/` on every
subdomain to Authentik.

The Minecraft chart is pinned to `5.1.3`: `5.2.0` changes an immutable
StatefulSet field, so upgrading needs
`kubectl -n minecraft delete sts minecraft --cascade=orphan` first.

## Working in the repo

`direnv allow` loads the dev shell, `KUBECONFIG=.kube/config`,
`BAO_ADDR=https://openbao.luukblankenstijn.nl`, and the state passphrase and S3
credentials from sops. Each OpenTofu root's `.envrc` adds only the secrets that
root needs.

Applies are manual, from the operator machine. CI
(`.github/workflows/check.yml`) runs `nix flake check`, which builds these docs
and evaluates the edge host, and builds the edge closure.

`nix build .#docs` builds this site with `mkdocs build --strict`: a broken link
or a page missing from `nav:` fails the build. `mkdocs serve` from the dev shell
previews it.
