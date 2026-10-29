{ config, pkgs, ... }:
let
  ports = builtins.fromJSON (builtins.readFile ./ports.json);
  domain = "relay.luukblankenstijn.nl";
  certDir = "/var/lib/acme/${domain}";
  relayConfig = (pkgs.formats.toml { }).generate "iroh-relay.toml" {
    http_bind_addr = "127.0.0.1:3340";
    enable_quic_addr_discovery = true;
    enable_metrics = true;
    metrics_bind_addr = "127.0.0.1:9091";
    access = "everyone";
    tls = {
      https_bind_addr = "[::]:${toString ports.irohRelayHttps}";
      quic_bind_addr = "[::]:${toString ports.irohRelayQad}";
      cert_mode = "Manual";
      manual_cert_path = "${certDir}/fullchain.pem";
      manual_key_path = "${certDir}/key.pem";
    };
  };
in
{
  sops.secrets.cloudflare-api-token = {
    sopsFile = ../../../secrets/cloudflare.yaml;
    key = "api_token";
  };
  sops.templates."acme-cloudflare.env".content = ''
    CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-api-token}
  '';

  security.acme = {
    acceptTerms = true;
    defaults.email = "git@luukblankenstijn.nl";
    certs.${domain} = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-cloudflare.env".path;
      group = config.users.groups.iroh-relay.name;
      reloadServices = [ "iroh-relay.service" ];
    };
  };

  users.users.iroh-relay = {
    isSystemUser = true;
    group = "iroh-relay";
  };
  users.groups.iroh-relay = { };

  systemd.services.iroh-relay = {
    description = "iroh relay";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "network-online.target"
      "acme-${domain}.service"
    ];
    after = [
      "network-online.target"
      "acme-${domain}.service"
    ];
    serviceConfig = {
      ExecStart = "${pkgs.iroh-relay}/bin/iroh-relay --config-path ${relayConfig}";
      User = "iroh-relay";
      Group = "iroh-relay";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
    };
  };

  networking.firewall.allowedTCPPorts = [ ports.irohRelayHttps ];
  networking.firewall.allowedUDPPorts = [ ports.irohRelayQad ];
}
