{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./frp.nix
    ./zigbee2mqtt.nix
    ./wifi.nix
  ];

  cfg = {
    server.enable = true;
    secrets = {
      file = ../../../secrets/home-gateway.yaml;
      password.enable = false;
    };
    networking.netbird = {
      enable = true;
      profiles.netbird.managementUrl = "https://netbird.luukblankenstijn.nl";
    };
    services = {
      comin = {
        enable = true;
        url = "https://github.com/LuukBlankenstijn/infra.git";
      };
      alloy = {
        enable = true;
        scrapeTargets.comin = "127.0.0.1:4243";
      };
    };
    deviceCert = {
      enable = true;
      secretsFile = ../../../secrets/openbao/home-gateway.yaml;
    };

    users.luuk = {
      git = {
        enable = true;
        extraSettings = {
          commit.gpgsign = false;
          tag.gpgsign = false;
        };
      };
      shell.enable = true;
    };
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  virtualisation.vmVariant.virtualisation.host.pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  system.stateVersion = "26.05";
}
