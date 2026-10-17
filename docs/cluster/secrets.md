# Secrets

Three stores, each for what the others cannot hold:

| Store | Holds | Read by |
| --- | --- | --- |
| sops, `secrets/*.yaml` | external credentials and bootstrap material needed before OpenBao or outside the cluster | direnv (`.envrc`) into OpenTofu; sops-nix on the NixOS hosts |
| SealedSecrets in `flux/` | the three secrets consumed at or before the `openbao` layer | the sealed-secrets controller |
| [OpenBao](openbao.md) | every other in-cluster secret | external-secrets, per-namespace SecretStores |

Nothing secret is committed in plain text.

## sops

`.sops.yaml` encrypts every `secrets/*.yaml` to the admin age key;
`secrets/edge.yaml` and `secrets/home-server.yaml` are also encrypted to that
host's age key so sops-nix can decrypt them on the host (see
[NixOS hosts](../hosts.md#secrets)).

| File | Keys | Consumed by |
| --- | --- | --- |
| `tofu.yaml` | `state_passphrase` | root `.envrc` → `TF_VAR_state_passphrase`, every root's state encryption |
| `s3.yaml` | `access_key_id`, `secret_access_key` | root `.envrc` → `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for the state backend; `40_s3-buckets` |
| `sealed-secrets.yaml` | `tls_crt`, `tls_key` | `20_cluster-bootstrap` (the pinned sealing key) |
| `edge.yaml` | `frp-token` | edge host (sops-nix); `40_openbao-config` → `secret/frpc/frpc` |
| `home-server.yaml` | `password` | home-server (sops-nix), login password of `luuk` |
| `apps.yaml` | `authentik.secret_key`, `authentik.smtp_password`, `vaultwarden.smtp_password` | `40_openbao-config` |
| `netbird.yaml` | `owner_email`, `owner_password`, `api_token`, `proxy_token` | `40_openbao-config` (`api_token`, `proxy_token`); `60_netbird-config` (`api_token`) |
| `cloudflare.yaml` | `api_token`, `zone_id` | `10_edge` |
| `hcloud.yaml` | `token` | `10_edge` |

`.envrc` decrypts with `sops_export VAR file [key]`; a file that does not decrypt
leaves the variable unset and logs it. `owner_email`/`owner_password` are the
break-glass NetBird login and are read by nothing (see
[NetBird](netbird.md#login)).

Edit a file with `sops secrets/<file>.yaml`.

## SealedSecrets

| SealedSecret | Keys | Layer | Why not OpenBao |
| --- | --- | --- | --- |
| `openbao/openbao-seal` | `key` | `openbao` | it is OpenBao's own seal key |
| `cert-manager/cloudflare-api-token` | `api-token` | `controllers` | cert-manager runs before OpenBao |
| `longhorn-system/backup-credentials` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS`, `AWS_REGION` | `controllers` | Longhorn runs before OpenBao and stores its volume |

A secret never sits in a layer that depends on the layer consuming it (see
[Flux layers](layers.md#rules)); these three are consumed at or before
`openbao`.

The sealing key is pinned. `terraform/20_cluster-bootstrap` writes
`sealed-secrets.yaml`'s `tls_crt`/`tls_key` into the Secret
`sealed-secrets/sealing-key-pinned` (label
`sealedsecrets.bitnami.com/sealed-secrets-key=active`) before Flux starts, and
the controller runs with `keyrenewperiod: 0`, so it never generates a key of its
own. A rebuilt cluster decrypts the SealedSecrets already in git.

Seal offline, without cluster access:

```sh
kubectl create secret generic <name> -n <namespace> --dry-run=client -o yaml \
  --from-literal=<key>=<value> \
  | kubeseal --cert <(sops -d --extract '["tls_crt"]' secrets/sealed-secrets.yaml) -o yaml \
  > flux/<layer>/<dir>/<name>-sealed-secret.yaml
```

The file name must end in `sealed-secret.yaml`: `.gitignore` ignores every other
`*secret.yaml`.

## Adding a secret

Pick by what the secret is:

| Secret | Change |
| --- | --- |
| Postgres or MariaDB credential | one map entry in `terraform/40_databases` (see [Postgres](../databases/postgres.md#adding-a-database)) |
| Object-storage bucket and key | one map entry in `terraform/40_s3-buckets` |
| Anything generated, or issued by a third party | one entry in `local.secrets` of `terraform/40_openbao-config/main.tf` |
| Needed by `controllers` or `openbao` | a SealedSecret, sealed as above |

For an `40_openbao-config` entry:

1. Add `"<namespace>/<name>" = { ... }` to `local.secrets`. Generate values with a
   `random_password`/`random_bytes` resource in the same file; put third-party
   values in `secrets/apps.yaml` (`sops secrets/apps.yaml`) and reference them
   through `local.app_secrets`.
2. Apply the root. It creates the path, its read policy, and role
   `secret-<namespace>` if the namespace is new.
3. In the namespace's Flux directory, add the ServiceAccount `openbao` and
   SecretStore `secret` if they do not exist yet, and an `ExternalSecret` reading
   `<namespace>/<name>`.
