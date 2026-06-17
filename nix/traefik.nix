{
  config,
  cfg,
  ...
}:
let
  certs = config.security.acme.certs;
  zitadelCert = certs.${cfg.zitadelHost}.directory;
  netbirdCert = certs.${cfg.netbirdHost}.directory;
  mgmtPort = config.services.netbird.server.management.port;
  signalPort = config.services.netbird.server.signal.port;
in
{
  services.traefik = {
    enable = true;

    staticConfigOptions = {
      entryPoints.web = {
        address = ":80";
        http.redirections.entryPoint = {
          to = "websecure";
          scheme = "https";
          permanent = true;
        };
      };
      entryPoints.websecure.address = ":443";
      log.level = "INFO";
      accessLog = { };
    };

    dynamicConfigOptions = {
      tls.certificates = [
        {
          certFile = "${zitadelCert}/fullchain.pem";
          keyFile = "${zitadelCert}/key.pem";
        }
        {
          certFile = "${netbirdCert}/fullchain.pem";
          keyFile = "${netbirdCert}/key.pem";
        }
      ];

      http.routers = {
        zitadel = {
          rule = "Host(`${cfg.zitadelHost}`)";
          service = "zitadel";
          entryPoints = [ "websecure" ];
          tls = { };
        };
        netbird-api = {
          rule = "Host(`${cfg.netbirdHost}`) && PathPrefix(`/api`)";
          service = "netbird-mgmt";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 100;
        };
        netbird-mgmt-grpc = {
          rule = "Host(`${cfg.netbirdHost}`) && PathPrefix(`/management.ManagementService`)";
          service = "netbird-mgmt-grpc";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 100;
        };
        netbird-signal-grpc = {
          rule = "Host(`${cfg.netbirdHost}`) && PathPrefix(`/signalexchange.SignalExchange`)";
          service = "netbird-signal-grpc";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 100;
        };
        # Browser (WASM) clients can't speak gRPC/h2c, so they reach mgmt and
        # signal through a WebSocket->gRPC bridge the servers expose under
        # /ws-proxy. These must hit the plain-HTTP (h2c) ports over HTTP/1.1 so
        # the WebSocket upgrade survives — routing them h2c would break it.
        netbird-wsproxy-mgmt = {
          rule = "Host(`${cfg.netbirdHost}`) && PathPrefix(`/ws-proxy/management`)";
          service = "netbird-mgmt";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 100;
        };
        netbird-wsproxy-signal = {
          rule = "Host(`${cfg.netbirdHost}`) && PathPrefix(`/ws-proxy/signal`)";
          service = "netbird-signal";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 100;
        };
        netbird-dashboard = {
          rule = "Host(`${cfg.netbirdHost}`)";
          service = "netbird-dashboard";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 1;
        };
      };

      http.services = {
        # Zitadel serves gRPC + REST + console on one HTTP/2 port; Traefik must
        # reach it over h2c (HTTP/2 cleartext), TLS terminated here on :443.
        zitadel.loadBalancer.servers = [ { url = "h2c://127.0.0.1:8081"; } ];
        netbird-mgmt.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString mgmtPort}"; }
        ];
        netbird-mgmt-grpc.loadBalancer.servers = [
          { url = "h2c://127.0.0.1:${toString mgmtPort}"; }
        ];
        netbird-signal-grpc.loadBalancer.servers = [
          { url = "h2c://127.0.0.1:${toString signalPort}"; }
        ];
        # Plain-HTTP view of signal for the /ws-proxy WebSocket bridge; the
        # h2c service above can't carry an HTTP/1.1 upgrade. Management reuses
        # its existing http "netbird-mgmt" service for the same reason.
        netbird-signal.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString signalPort}"; }
        ];
        netbird-dashboard.loadBalancer.servers = [
          { url = "http://127.0.0.1:8080"; }
        ];
      };
    };
  };

  # Traefik starts before ACME issues the certs on a fresh deploy, so it must be
  # bounced when each cert lands — otherwise it serves its default self-signed
  # cert and HTTPS to the IdP / dashboard fails until a manual restart.
  security.acme.certs.${cfg.zitadelHost}.reloadServices = [ "traefik.service" ];
  # netbird-relay also holds the cert in memory at startup and never reloads, so
  # ACME has to bounce it on renewal — otherwise the relay keeps serving the
  # initial minica self-signed cert and clients reject the TLS handshake.
  security.acme.certs.${cfg.netbirdHost}.reloadServices = [
    "netbird-relay.service"
    "traefik.service"
  ];
}
