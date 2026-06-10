{
  config,
  cfg,
  ...
}:
let
  kanidmIssuer = "https://${cfg.kanidmHost}/oauth2/openid/netbird";
  oauth2SecretFile = "/var/lib/netbird-mgmt/secrets/oidc-client-secret";
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
      oidcConfigEndpoint = "${kanidmIssuer}/.well-known/openid-configuration";
      settings = {
        IdpManagerConfig.ManagerType = "none";
        # kanidm 1.10 doesn't ship OAuth2 device authorization grant, so we
        # can't offer device flow. Headless / SSH machines must enroll with
        # a setup key from the dashboard; PKCE covers desktop with a browser.
        DeviceAuthorizationFlow.Provider = "none";

        PKCEAuthorizationFlow.ProviderConfig = {
          Audience = "netbird";
          ClientID = "netbird";
          # Public PKCE client: kanidm expects no client_secret in token req.
          ClientSecret = "";
          AuthorizationEndpoint = "https://${cfg.kanidmHost}/ui/oauth2";
          TokenEndpoint = "https://${cfg.kanidmHost}/oauth2/token";
          Scope = "openid profile email groups offline_access";
          # Order matters: CLI clients pick the loopback URL; the dashboard
          # picks the URL matching its origin. List localhost first to keep
          # the CLI off the dashboard's /auth handler.
          RedirectURLs = [
            "http://localhost:53000"
            "https://${cfg.netbirdHost}/auth"
          ];
          UseIDToken = true;
        };

        HttpConfig = {
          AuthIssuer = kanidmIssuer;
          AuthAudience = "netbird";
          AuthUserIDClaim = "sub";
          AuthKeysLocation = "${kanidmIssuer}/public_key.jwk";
        };

        DataStoreEncryptionKey._secret =
          config.sops.secrets."netbird/datastore-encryption-key".path;

        Relay = {
          Addresses = [ "rels://${cfg.netbirdHost}:33080" ];
          CredentialsTTL = "24h";
          Secret._secret = config.sops.secrets."netbird/relay-auth-secret".path;
        };
      };
    };

    dashboard.settings = {
      AUTH_AUTHORITY = kanidmIssuer;
      AUTH_CLIENT_ID = "netbird";
      AUTH_AUDIENCE = "netbird";
      AUTH_SUPPORTED_SCOPES = "openid profile email groups";
      AUTH_REDIRECT_URI = "/auth";
      AUTH_SILENT_REDIRECT_URI = "/silent-auth";
      NETBIRD_TOKEN_SOURCE = "idToken";
    };
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
