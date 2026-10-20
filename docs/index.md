# Home infrastructure

One repository for the home k3s cluster (`home-server`, a single node on the
home LAN at `192.168.1.78`), the public edge VPS, the NixOS hosts they run on,
and the OpenTofu roots that configure what runs on them.

| Directory | Contents |
| --- | --- |
| `flux/` | Everything the cluster runs, reconciled by Flux in numbered layers. See [Flux layers](cluster/layers.md). |
| `terraform/` | OpenTofu roots. The two-digit prefix is the apply order on a fresh setup; equal prefixes are independent. See [Roots](terraform/roots.md). |
| `nix/` | The NixOS hosts `edge`, `home-server` and `home-gateway` (`nix/hosts/`), the dev shell, `mint-kubeconfig` and the docs build. See [NixOS hosts](hosts.md). |
| `secrets/` | sops-encrypted bootstrap material needed before OpenBao exists. See [Secrets](cluster/secrets.md). |

## What runs where

| Piece | Page |
| --- | --- |
| Operating systems of the edge, the k3s node and Home Assistant | [NixOS hosts](hosts.md) |
| Internet → edge VPS → frp tunnel → Traefik | [Edge and public ingress](cluster/edge.md) |
| `kubectl`, Helm and OpenTofu against the cluster | [Cluster access](cluster/access.md) |
| Secret storage and delivery into namespaces | [OpenBao](cluster/openbao.md), [Secrets](cluster/secrets.md) |
| Mesh VPN, login, Kubernetes API over the mesh | [NetBird](cluster/netbird.md) |
| Services published through NetBird | [NetBird reverse proxy](cluster/reverse-proxy.md) |
| Shared database servers | [Postgres](databases/postgres.md), [MariaDB](databases/mariadb.md) |
| What is backed up, where, and how to restore | [Backups](databases/backups.md) |
| Metrics, logs, Grafana, device ingest over mTLS | [Observability](observability/index.md) |
| Alerts to the phone through ntfy | [Alerting](observability/alerting.md) |

## Applications

Everything in `flux/50_apps`. Hostnames are under `luukblankenstijn.nl`.

| App | Host | State |
| --- | --- | --- |
| Android emulator | `android`, behind Authentik forward auth; control for `infra-admins`. See [Android emulator](apps/android-emul.md) | Longhorn volume `data` |
| Authentik | `auth` | Postgres `authentik` |
| Grafana | `grafana`; device ingest on `logs` and `metrics`, mTLS only | Postgres `grafana`; Loki and Mimir in buckets `luuk-loki`, `luuk-mimir` |
| Grimmory | `grimmory` | MariaDB `grimmory`, Longhorn volumes `data`, `books` |
| Home Assistant | `home-assistant`, mTLS only; zigbee2mqtt frontend on `zigbee2mqtt`, mTLS only; MQTT on `mqtt`, client certificate. See [Home Assistant](apps/home-assistant.md) | Longhorn volumes `config`, `mosquitto` |
| Longhorn UI | `longhorn`, behind Authentik forward auth | - |
| Minecraft | Traefik entrypoints `minecraft` (25565/tcp) and `voicechat-udp` (24454/udp) on the node | Longhorn volume |
| ntfy | `ntfy`, mTLS only | Longhorn volume `data` (SQLite) |
| NetBird | `netbird` | Postgres `netbird`, `netbird_events`, `netbird_idp`, Longhorn volume `netbird-data` |
| Ollama | no ingress; NetBird sidecar only | Longhorn volume for models |
| Shelfmark | `shelfmark`, behind Authentik forward auth | Longhorn volumes `books`, `config`, `downloads` |
| Traefik dashboard | `traefik`, behind Authentik forward auth | - |
| Vaultwarden | `vaultwarden` | Postgres `vaultwarden`, volume `data` |

Forward auth is the Traefik Middleware `authentik/proxy-auth`. The proxy
providers, their applications and access bindings, and the embedded outpost are
OpenTofu in `terraform/50_authentik-config/forward-auth.tf`; a new forward-auth
app is one entry in `local.forward_auth_apps`. Every app is bound to group
`infra-admins`; `public = true` also binds group `public`, whose members are
managed in the Authentik UI. Shelfmark is additionally open to group
`Booklore`. The IngressRoute `authentik/auth-redirect` sends
`/outpost.goauthentik.io/` on every subdomain to Authentik.

Every Minecraft chart version changes the `chart` label in the StatefulSet's
`volumeClaimTemplates`, an immutable field, so Renovate does not automerge it.
To upgrade: `flux -n minecraft suspend hr minecraft`, merge the bump, wait until
`flux -n minecraft get sources chart` shows the new version, then
`kubectl -n minecraft delete sts minecraft --cascade=orphan` and
`flux -n minecraft resume hr minecraft`.

## Working in the repo

`direnv allow` loads the dev shell, `KUBECONFIG=.kube/netbird.yaml:.kube/config`,
`BAO_ADDR=https://openbao.luukblankenstijn.nl`, and the state passphrase and S3
credentials from sops. Each OpenTofu root's `.envrc` adds only the secrets that
root needs.

OpenTofu applies are manual, from the operator machine; the NixOS hosts deploy
themselves with comin (see [NixOS hosts](hosts.md#deploying)). CI
(`.github/workflows/check.yml`) runs `nix flake check`, which builds these docs
and evaluates every host, and builds every host's closure (`home-gateway` on
an arm64 runner). It runs only when the flake, `nix/`, `secrets/`,
`.sops.yaml`, the docs or the workflow change. The `flake` job sums up the
others and is the required check on `main`; it passes when they are skipped.

`nix build .#docs` builds this site with `mkdocs build --strict`: a broken link
or a page missing from `nav:` fails the build. `mkdocs serve` from the dev shell
previews it.
