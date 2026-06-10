{
  description = "Standalone IdP (kanidm) + NetBird host on Hetzner Cloud";

  inputs = {
    # Unstable channel for newer netbird / kanidm. flake.lock pins the exact
    # commit, so updates are deliberate (nix flake update) — no auto-drift.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning consumed by nixos-anywhere.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # tmpfs root + opt-in persisted paths.
    impermanence.url = "github:nix-community/impermanence";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      sops-nix,
      disko,
      impermanence,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs { inherit system; };

      cfg = import ./nix/_config.nix;
    in
    {
      nixosConfigurations.netbird-host = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs cfg; };
        modules = [
          sops-nix.nixosModules.sops
          disko.nixosModules.disko
          ./nix/host.nix
          ./nix/hetzner.nix
          ./nix/disko.nix
          ./nix/traefik.nix
          ./nix/kanidm
          ./nix/netbird
        ];
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            name = "infra-base";

            packages = with pkgs; [
              opentofu
              nixos-anywhere
              sops
              age
              ssh-to-age
              hcloud
              awscli2
              kanidm_1_10
              mkpasswd
              nixpkgs-fmt
              nix-output-monitor
              git
              jq
              yq-go
              curl
              openssl
            ];

            shellHook = ''
              echo "infra-base devshell — $(tofu version | head -n1)"
              echo "nixpkgs:    ${nixpkgs.rev or "dirty"} (nixos-unstable)"
            '';
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
