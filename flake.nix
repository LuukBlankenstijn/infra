{
  description = "Home infrastructure: k3s cluster, edge VPS, OpenTofu roots";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, sops-nix, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.edge = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          sops-nix.nixosModules.sops
          ./nix/hosts/edge
        ];
      };

      packages = forAllSystems (system: {
        docs = import ./nix/packages/docs.nix { pkgs = pkgsFor system; };
      });

      checks = forAllSystems (system: {
        docs = import ./nix/packages/docs.nix { pkgs = pkgsFor system; };
      });

      devShells = forAllSystems (system: {
        default = import ./nix/devshell.nix { pkgs = pkgsFor system; };
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
