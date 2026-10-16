{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./frp.nix
    ./stun.nix
  ];

  networking.hostName = "edge";
  time.timeZone = "Europe/Amsterdam";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };

  users.users.luuk = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ./authorized_keys ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking.firewall.enable = true;

  sops.defaultSopsFile = ../../../secrets/edge.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  environment.systemPackages = with pkgs; [
    git
    vim
    bind
    jq
  ];

  system.stateVersion = "25.05";
}
