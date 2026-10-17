# NixOS hosts

The machines that serve the infrastructure are defined here; the modules they
are built from live in [nix-config](https://github.com/LuukBlankenstijn/nix-config),
which also defines the laptops.

| Host | System | Address | Role |
| --- | --- | --- | --- |
| `edge` | `x86_64-linux` | `49.12.197.36` | public ingress, see [Edge](cluster/edge.md) |
| `home-server` | `x86_64-linux` | `192.168.1.78` | the k3s node |
| `home-assistant` | `aarch64-linux` | LAN, Raspberry Pi booting from a USB SSD | Home Assistant |

## How a host is built

`flake.nix` passes each `nix/hosts/<host>/configuration.nix` to
`nix-config.lib.mkHost`. `mkHost` builds with nix-config's own inputs (its
`nixpkgs`, home-manager, sops-nix, comin, `ssh-keys`) and adds every nix-config
module, so a host only sets `cfg.*` options plus what is specific to it. This
flake's `nixpkgs` follows `nix-config/nixpkgs`; nothing else pins a package set.

Options every host here sets:

| Option | Value |
| --- | --- |
| `cfg.server.enable` | sshd, keys from `https://github.com/LuukBlankenstijn.keys`, passwordless sudo, firewall with 22/tcp open |
| `cfg.services.comin.url` | `https://github.com/LuukBlankenstijn/infra.git` |
| `cfg.secrets.file` | this repo's `secrets/<host>.yaml`; `home-assistant` has none |

## Deploying

comin on each host polls `main` of this repository and switches to
`nixosConfigurations.<hostname>` when its output changes. A merged commit is a
deploy.

comin only deploys a `main` that descends from the commit it deployed last. A
host whose comin followed another repository rejects this one until its state is
reset: deploy it once by hand, then `systemctl stop comin`, move `/var/lib/comin`
aside and start comin again.

nix-config is a flake input pinned in `flake.lock`. Renovate opens a PR when
nix-config's `main` moves and automerges it once `check` passes, so a change to a
shared module reaches these hosts without a manual bump.

To deploy by hand, building on the target:

```sh
nixos-rebuild switch --flake .#<host> \
  --target-host luuk@<address> --build-host luuk@<address> --sudo
```

For a NixOS release jump use `boot` and reboot: switching across releases on a
running host can hang it.

`check` evaluates every host (`nix flake check`) and builds each host's closure,
`home-assistant` on an arm64 runner.

## Secrets

sops-nix decrypts `secrets/<host>.yaml` with the age key derived from the host's
`/etc/ssh/ssh_host_ed25519_key`. `.sops.yaml` encrypts that file to the admin
key and the host's key; see [Secrets](cluster/secrets.md#sops).

| File | Keys | Used for |
| --- | --- | --- |
| `edge.yaml` | `frp-token` | frps |
| `home-server.yaml` | `password` | hashed login password for `luuk` |
| `openbao/home-assistant.yaml` | `openbao/role_id`, `openbao/secret_id` | AppRole `device-home-assistant` for nix-config's `cfg.services.alloy`; encrypted only to the admin key, so the host needs its recipient added before it can enable Alloy |

A reinstalled host has a new SSH host key, so its recipient in `.sops.yaml`
changes and the file needs `sops updatekeys` before sops-nix can decrypt.
