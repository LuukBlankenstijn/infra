{
  config,
  cfg,
  ...
}:
let
  zitadelIssuer = "https://${cfg.zitadelHost}";
  # Generated Zitadel client IDs/secret are delivered here by the tofu/zitadel
  # module (out of band), then read into management.json at preStart via the
  # netbird module's `_secret` substitution. The host config only references the
  # stable paths — the values themselves never live in Nix.
  oidcDir = "/var/lib/netbird-oidc";
in
{
  imports = [
    ./dashboard.nix
    ./relay.nix
  ];

  services.netbird.server = {
    enable = true;
    domain = cfg.netbirdHost;
    enableNginx = false;

    coturn = {
      enable = true;
      passwordFile = config.sops.secrets."netbird/coturn-password".path;
      # Narrow the firewall opening: only the STUN/TURN listening port. The
      # default also opens alt-, TLS, and alt-TLS listeners we don't use.
      openPorts = [ config.services.coturn.listening-port ];
    };

    management = {
      # Default 9090 collides with netbird-relay (which binds its own :9090).
      metricsPort = 9092;
      logLevel = "INFO";
      oidcConfigEndpoint = "${zitadelIssuer}/.well-known/openid-configuration";
      settings = {
        # Zitadel IS in NetBird's managed-IdP list, so unlike kanidm we run the
        # full integration: user sync + invites work, no manual import dance.
        # The idp-mgmt service user (client_credentials, ORG_USER_MANAGER) is
        # created by tofu; its id/secret arrive in oidcDir.
        IdpManagerConfig = {
          ManagerType = "zitadel";
          ClientConfig = {
            Issuer = zitadelIssuer;
            TokenEndpoint = "${zitadelIssuer}/oauth/v2/token";
            ClientID._secret = "${oidcDir}/idp-client-id";
            ClientSecret._secret = "${oidcDir}/idp-client-secret";
            GrantType = "client_credentials";
          };
          ExtraConfig.ManagementEndpoint = "${zitadelIssuer}/management/v1";
        };

        # The whole point of the migration: Zitadel ships the OAuth2 device
        # authorization grant, so headless / SSH peers enroll without a setup
        # key. Provider "hosted" auto-discovers the device/token endpoints.
        DeviceAuthorizationFlow = {
          Provider = "hosted";
          ProviderConfig = {
            Audience._secret = "${oidcDir}/cli-client-id";
            ClientID._secret = "${oidcDir}/cli-client-id";
            Scope = "openid";
            UseIDToken = true;
          };
        };

        PKCEAuthorizationFlow.ProviderConfig = {
          Audience._secret = "${oidcDir}/cli-client-id";
          ClientID._secret = "${oidcDir}/cli-client-id";
          AuthorizationEndpoint = "${zitadelIssuer}/oauth/v2/authorize";
          TokenEndpoint = "${zitadelIssuer}/oauth/v2/token";
          Scope = "openid profile email offline_access";
          # Order matters: CLI clients pick the loopback URL; the dashboard
          # picks the URL matching its origin. Keep localhost first.
          RedirectURLs = [
            "http://localhost:53000/"
            "http://localhost:54000/"
          ];
          UseIDToken = true;
        };

        HttpConfig = {
          AuthIssuer = zitadelIssuer;
          # Zitadel puts the project id in every token's `aud` (dashboard AND
          # cli/device), so the project id is the one value that validates both
          # browser and device-flow tokens. tofu/zitadel delivers it here.
          AuthAudience._secret = "${oidcDir}/audience";
        };

        DataStoreEncryptionKey._secret = config.sops.secrets."netbird/datastore-encryption-key".path;

        Relay = {
          Addresses = [ "rels://${cfg.netbirdHost}:33080" ];
          CredentialsTTL = "24h";
          Secret._secret = config.sops.secrets."netbird/relay-auth-secret".path;
        };
      };
    };

    dashboard.settings = {
      AUTH_AUTHORITY = zitadelIssuer;
      AUTH_SUPPORTED_SCOPES = "openid profile email offline_access";
      AUTH_REDIRECT_URI = "/auth";
      AUTH_SILENT_REDIRECT_URI = "/silent-auth";
      NETBIRD_TOKEN_SOURCE = "idToken";
      # Zitadel generates the client id, unknown at Nix eval time. Bake a unique
      # sentinel into the static build; netbird-dashboard-render (dashboard.nix)
      # sed-replaces it at runtime with the tofu-delivered value.
      AUTH_CLIENT_ID = "@@NETBIRD_CLIENT_ID@@";
      AUTH_AUDIENCE = "@@NETBIRD_CLIENT_ID@@";
    };
  };

  # tofu/zitadel writes the four generated values here over SSH, then restarts
  # netbird. root-owned (netbird-management runs as root); secret is 0400.
  systemd.tmpfiles.rules = [
    "d ${oidcDir} 0750 root root -"
  ];

  # On a fresh box (before the tofu phase has delivered the IDs) hold the
  # service instead of crash-looping; the tofu `systemctl restart` re-checks
  # the condition once the files exist.
  systemd.services.netbird-management = {
    after = [ "zitadel.service" ];
    unitConfig.ConditionPathExists = "${oidcDir}/cli-client-id";
  };

  # Narrow the TURN media-relay range so the Hetzner Cloud firewall rule
  # stays a tight ~100-port window instead of the coturn default 16384.
  services.coturn = {
    min-port = 49152;
    max-port = 49251;
  };

  sops.secrets."netbird/coturn-password" = {
    owner = "turnserver";
    restartUnits = [
      "coturn.service"
      "netbird-management.service"
    ];
  };

  sops.secrets."netbird/datastore-encryption-key".restartUnits = [
    "netbird-management.service"
  ];
}
