{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./frp.nix
    ./stun.nix
  ];

  cfg = {
    server.enable = true;
    secrets = {
      file = ../../../secrets/edge.yaml;
      password.enable = false;
    };
    services.comin = {
      enable = true;
      url = "https://github.com/LuukBlankenstijn/infra.git";
    };
    users.luuk.shell.enable = true;
  };

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  services.openssh.settings.PermitRootLogin = "no";

  system.stateVersion = "25.05";
}
