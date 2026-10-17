{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./frp.nix
    ./stun.nix
    ./heartbeat.nix
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
    services.alloy = {
      enable = true;
      openbao = {
        enable = true;
        secretsFile = ../../../secrets/openbao/edge.yaml;
      };
      scrapeTargets = {
        comin = "127.0.0.1:4243";
        frps = "127.0.0.1:7500";
      };
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
