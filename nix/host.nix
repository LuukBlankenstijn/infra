{
  config,
  cfg,
  ...
}:
{
  networking.hostName = "netbird-host";
  networking.domain = cfg.domain;
  time.timeZone = cfg.timeZone;
  system.stateVersion = "26.05";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" ];
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  users.mutableUsers = false;
  users.users.root.openssh.authorizedKeys.keys = cfg.rootAuthorizedKeys;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
    };
  };

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  sops.secrets."acme/cloudflare-token-env" = {
    mode = "0400";
    restartUnits = [
      "acme-${cfg.kanidmHost}.service"
      "acme-${cfg.netbirdHost}.service"
    ];
  };

  security.acme = {
    acceptTerms = true;
    defaults = {
      email = cfg.adminEmail;
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets."acme/cloudflare-token-env".path;
      group = "traefik";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 33080 ];
  };
}
