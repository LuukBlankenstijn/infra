{
  config,
  pkgs,
  cfg,
  ...
}:
let
  acmeDir = config.security.acme.certs.${cfg.kanidmHost}.directory;
in
{
  imports = [
    ./bootstrap.nix
    ./mail-sender.nix
  ];

  services.kanidm = {
    server.enable = true;
    package = pkgs.kanidmWithSecretProvisioning_1_10;

    server.settings = {
      domain = cfg.kanidmHost;
      origin = "https://${cfg.kanidmHost}";
      bindaddress = "127.0.0.1:8443";
      ldapbindaddress = null;
      tls_chain = "${acmeDir}/fullchain.pem";
      tls_key = "${acmeDir}/key.pem";
      # Tighten later: kanidm 1.10 replaced trust_x_forward_for with
      # http_client_address_info — pass the Traefik loopback CIDR there.
      online_backup = {
        path = "/var/lib/kanidm/backups";
        versions = 7;
      };
    };

    provision = {
      enable = true;
      autoRemove = false;
      idmAdminPasswordFile = config.sops.secrets."kanidm/idm-admin-password".path;
      adminPasswordFile = config.sops.secrets."kanidm/admin-password".path;
      instanceUrl = "https://127.0.0.1:8443";
      # Loopback-only connection; the cert SAN is the public hostname, so
      # hostname-based verification fails. Accepting localhost is safe.
      acceptInvalidCerts = true;

      groups.infra_admins.members = [ cfg.adminUser.name ];

      persons.${cfg.adminUser.name} = {
        inherit (cfg.adminUser) displayName legalName mailAddresses;
        groups = [ "infra_admins" ];
      };

      systems.oauth2.netbird = {
        displayName = "NetBird";
        # Public/PKCE client — the dashboard is a SPA and can't keep a
        # client_secret. Kanidm enforces PKCE automatically for public
        # clients, so the desktop loopback flow is also covered.
        public = true;
        # Kanidm 1.10 requires EXACT redirect URI match. These must be the
        # exact URIs the dashboard / desktop client hand to /ui/oauth2.
        originUrl = [
          "https://${cfg.netbirdHost}/auth"
          "https://${cfg.netbirdHost}/silent-auth"
          "http://localhost:53000"
        ];
        originLanding = "https://${cfg.netbirdHost}/";
        scopeMaps.infra_admins = [ "openid" "email" "profile" "groups" "offline_access" ];
        claimMaps.groups = {
          joinType = "array";
          valuesByGroup.infra_admins = [ "netbird_admins" ];
        };
        preferShortUsername = true;
      };
    };
  };

  users.users.kanidm.extraGroups = [ "traefik" ];

  sops.secrets."kanidm/idm-admin-password" = {
    owner = "kanidm";
    restartUnits = [ "kanidm.service" ];
  };
  sops.secrets."kanidm/admin-password" = {
    owner = "kanidm";
    restartUnits = [ "kanidm.service" ];
  };
}
