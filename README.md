# infra

Home infrastructure in one repository:

- `flux/`: the k3s cluster, reconciled by Flux
- `nix/hosts/`: the NixOS hosts (edge, home-server, home-gateway), built on
  [nix-config](https://github.com/LuukBlankenstijn/nix-config)'s modules and
  deployed by comin
- `terraform/`: OpenTofu roots

Docs are in `docs/`; build them with `nix build .#docs`.
