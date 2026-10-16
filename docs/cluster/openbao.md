# OpenBao

OpenBao 2.7.1 (`flux/30_openbao`, chart `0.30.4`): one Raft replica on a 1 Gi
`longhorn` volume, sealed with a static key, reached at
`https://openbao.luukblankenstijn.nl` through Traefik and in-cluster at
`http://openbao-active.openbao.svc:8200`. The listener has no TLS of its own;
Traefik terminates it with the wildcard certificate. The agent injector is off;
secrets reach pods only through external-secrets.

## Seal

The `seal "static"` stanza reads its key from `BAO_SEAL_KEY`, which comes from
key `key` of the SealedSecret `openbao/openbao-seal`. OpenBao unseals itself on
every start; nobody holds unseal shares. The Raft data is useless without that
key, so a restore of the volume needs the same SealedSecret (and therefore the
pinned sealing key, see [Secrets](secrets.md#sealedsecrets)).

## Self-initialisation

The `initialize "auth"` stanza runs on first start against empty storage. It:

1. enables the `kubernetes` auth method against `https://kubernetes.default.svc`;
2. writes the `admin` policy: `create`, `update`, `read`, `delete`, `list`,
   `scan` and `sudo` on `*`;
3. creates role `admin`, bound to ServiceAccount `openbao/openbao-admin`
   (`flux/30_openbao/admin-serviceaccount.yaml`), token TTL 1h.

The root token generated during initialisation is revoked. The only way in is
that ServiceAccount.

## Logging in

```sh
bao write auth/kubernetes/login role=admin \
  jwt="$(kubectl -n openbao create token openbao-admin)"
```

`BAO_ADDR` is set by the root `.envrc`. For OpenTofu, `bao_jwt_export` (root
`.envrc`) mints the same token into `TF_VAR_bao_jwt` with a 5-second request
timeout; without a working [LAN kubeconfig](access.md#the-lan-kubeconfig) the
variable stays unset. Every root with a `vault` provider calls it and logs in
through `auth/kubernetes/login` as `admin`.

## Mounts

The KV v2 mounts are owned by one root each:

| Mount | Root | Contents | Path layout |
| --- | --- | --- | --- |
| `secret` | `40_openbao-config` | generated application secrets and values copied from sops | `<namespace>/<name>` |
| `postgres` | `40_databases` | Postgres role credentials | `<namespace>/<database>` |
| `mariadb` | `40_databases` | MariaDB user credentials | `<namespace>/<database>` |
| `s3` | `40_s3-buckets` | Hetzner Object Storage credentials per bucket | `<namespace>/<consumer>` |
| `authentik` | `50_authentik-config` | Authentik OIDC client credentials | `<namespace>/<client>` |

`50_pki` writes one path into `secret` that it owns itself,
`observability/device-ca`, and owns the PKI mounts and the AppRole auth mount
(see [Observability](../observability/index.md#device-ca)):

| Mount | Type | Contents |
| --- | --- | --- |
| `pki-devices` | PKI | root CA `Home device CA`; signs only the intermediates |
| `pki-hosts` | PKI | intermediate for host client certificates; one role per host |
| `pki-phone-<name>` | PKI | one intermediate and one client certificate per phone |
| `auth/approle` | auth | AppRole `device-<host>` per host, allowed only `pki-hosts/issue/<host>` |

## Roles and policies

For `secret`, `postgres`, `mariadb` and `s3` the owning root creates, per entry, a
read-only policy on exactly that path, and per consuming namespace a Kubernetes
auth role `<mount>-<namespace>` (for example `secret-netbird`,
`postgres-authentik`, `s3-mariadb`). The role is bound to every ServiceAccount
in that namespace, carries the policies for that namespace's paths, and issues
1-hour tokens. A namespace can therefore read its own paths and nothing else.

`authentik` follows the same pattern: `50_authentik-config` creates policy
`authentik-observability-grafana` and role `authentik-observability` for
Grafana's client. `authentik/netbird/netbird` has no Kubernetes role; only
`60_netbird-config` reads it, as `admin`.

`secret/observability/device-ca` is read from namespace `traefik` through role
`pki-traefik` (policy `pki-traefik-device-ca`), owned by `50_pki`. It is not
named `secret-traefik` so it cannot collide with a role `40_openbao-config`
would create for that namespace; the SecretStore using it is `traefik/pki`.

## Consuming a secret

Each consuming namespace holds a ServiceAccount `openbao` and one namespaced
`SecretStore` per mount, named after the mount:

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: secret
  namespace: <namespace>
spec:
  provider:
    vault:
      server: http://openbao-active.openbao.svc:8200
      path: secret
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: secret-<namespace>
          serviceAccountRef:
            name: openbao
```

`ExternalSecret`s then reference keys as `<namespace>/<name>` with a `property`,
or extract the whole path with `dataFrom` and a template. In `postgres` and
`mariadb` the backup credentials use a ServiceAccount and SecretStore named `s3`.
