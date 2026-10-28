{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  cfg = {
    server.enable = true;
    secrets.file = ../../../secrets/home-server.yaml;
    services.comin = {
      enable = true;
      url = "https://github.com/LuukBlankenstijn/infra.git";
    };
    services.k3s = {
      enable = true;
      gpu.enable = true;
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
      clipboard.enable = true;
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction = "ignore";
  };

  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  boot.kernel.sysctl."net.ipv6.conf.enp3s0.disable_ipv6" = 1;
  networking.dhcpcd.extraConfig = "noipv6rs";

  environment.etc."k3s-resolv.conf".text = ''
    nameserver 1.1.1.1
    nameserver 8.8.8.8
  '';
  services.k3s.extraFlags = [ "--resolv-conf=/etc/k3s-resolv.conf" ];
  services.k3s.package = pkgs.k3s_1_36;
  services.k3s.extraKubeletConfig = {
    imageGCHighThresholdPercent = 65;
    imageGCLowThresholdPercent = 55;
  };

  services.prometheus.exporters = {
    smartctl.enable = true;
    nvidia-gpu.enable = true;
  };
  networking.firewall.interfaces.cni0.allowedTCPPorts = [
    4243
    9633
    9835
  ];

  system.stateVersion = "25.05";
}
