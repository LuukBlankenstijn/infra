{
  description = "Home infrastructure: k3s cluster, its NixOS hosts, OpenTofu roots";

  inputs = {
    nix-config.url = "github:LuukBlankenstijn/nix-config";
    nixpkgs.follows = "nix-config/nixpkgs";
  };

  outputs =
    { nixpkgs, nix-config, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
      host =
        hostname: system:
        nix-config.lib.mkHost {
          inherit hostname system;
          modules = [ ./nix/hosts/${hostname}/configuration.nix ];
        };
      nixosConfigurations = {
        edge = host "edge" "x86_64-linux";
        home-server = host "home-server" "x86_64-linux";
        home-gateway = host "home-gateway" "aarch64-linux";
      };
      sdImage =
        hostname:
        (nixosConfigurations.${hostname}.extendModules {
          modules = [ "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix" ];
        }).config.system.build.sdImage;
    in
    {
      inherit nixosConfigurations;

      packages = forAllSystems (
        system:
        {
          docs = import ./nix/packages/docs.nix { pkgs = pkgsFor system; };
        }
        // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
          home-gateway-sd-image = sdImage "home-gateway";
        }
      );

      checks = forAllSystems (system: {
        docs = import ./nix/packages/docs.nix { pkgs = pkgsFor system; };
      });

      devShells = forAllSystems (system: {
        default = import ./nix/devshell.nix { pkgs = pkgsFor system; };
      });

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
