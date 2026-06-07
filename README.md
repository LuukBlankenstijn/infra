# infra-base

A standalone NixOS host on Hetzner Cloud running **kanidm** (IdP) and the **NetBird** management/control plane.

- `DESIGN.md` — the design brief that drives every decision.
- `NOTES.md` — operator checklist + open items.
- `nix/` — `nixosConfigurations.netbird-host` and its modules.
- `tofu/host/` — provisions the VM, DNS, and runs nixos-anywhere.
- `tofu/netbird-account/` — reconciles NetBird groups, policies, setup keys.

## Workflow

```sh
nix develop                                    # enter the devshell

cd tofu/host && tofu init && tofu apply        # first-time host
cd tofu/netbird-account && tofu init && tofu apply
```

CI: `nix flake check` on every PR; `tofu plan` posted on PRs for both modules; `netbird-account` applies on merge; **host** apply is `workflow_dispatch` only.
