{ inputs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  cfg = {
    server.enable = true;
    secrets.password.enable = false;
    networking.netbird = {
      enable = true;
      profiles.netbird.managementUrl = "https://netbird.luukblankenstijn.nl";
    };
    services = {
      comin = {
        enable = true;
        url = "https://github.com/LuukBlankenstijn/infra.git";
      };
      home-assistant.enable = true;
    };

    users.luuk = {
      git = {
        enable = true;
        extraSettings = {
          commit.gpgsign = false;
          tag.gpgsign = false;
        };
      };
      neovim.enable = true;
      shell.enable = true;
    };
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  virtualisation.vmVariant.virtualisation.host.pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;

  system.stateVersion = "26.05";
}
