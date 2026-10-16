# Home infrastructure

One repository for the home k3s cluster (`home-server`, single node on the home
LAN), the public edge VPS, and the OpenTofu roots that configure what runs on
them.

| Directory | Contents |
| --- | --- |
| `flux/` | Everything the cluster runs, reconciled by Flux in numbered layers. See [Flux layers](cluster/layers.md). |
| `terraform/` | OpenTofu roots. The two-digit prefix is the apply order on a fresh setup; equal prefixes are independent. |
| `nix/` | The edge host (`nixosConfigurations.edge`) and the dev shell. |
| `secrets/` | sops-encrypted bootstrap material needed before OpenBao exists. |

## Working in the repo

`direnv allow` loads the dev shell, `KUBECONFIG=.kube/config`, and the state
passphrase and S3 credentials from sops. Each OpenTofu root's `.envrc` adds only
the secrets that root needs.
