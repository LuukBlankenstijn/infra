{
  config,
  cfg,
  ...
}:
let
  certs = config.security.acme.certs;
  kanidmCert = certs.${cfg.kanidmHost}.directory;
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
        { certFile = "${kanidmCert}/fullchain.pem"; keyFile = "${kanidmCert}/key.pem"; }
        { certFile = "${netbirdCert}/fullchain.pem"; keyFile = "${netbirdCert}/key.pem"; }
      ];

      # kanidm presents the public cert on its localhost listener; rather
      # than dragging in a trust-root chain just for a 127.0.0.1 hop, skip
      # verification on this upstream — the security boundary is the host.
      http.serversTransports.kanidm.insecureSkipVerify = true;

      http.routers = {
        kanidm = {
          rule = "Host(`${cfg.kanidmHost}`)";
          service = "kanidm";
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
        netbird-dashboard = {
          rule = "Host(`${cfg.netbirdHost}`)";
          service = "netbird-dashboard";
          entryPoints = [ "websecure" ];
          tls = { };
          priority = 1;
        };
      };

      http.services = {
        kanidm.loadBalancer = {
          servers = [ { url = "https://127.0.0.1:8443"; } ];
          serversTransport = "kanidm";
        };
        netbird-mgmt.loadBalancer.servers = [
          { url = "http://127.0.0.1:${toString mgmtPort}"; }
        ];
        netbird-mgmt-grpc.loadBalancer.servers = [
          { url = "h2c://127.0.0.1:${toString mgmtPort}"; }
        ];
        netbird-signal-grpc.loadBalancer.servers = [
          { url = "h2c://127.0.0.1:${toString signalPort}"; }
        ];
        netbird-dashboard.loadBalancer.servers = [
          { url = "http://127.0.0.1:8080"; }
        ];
      };
    };
  };

  security.acme.certs.${cfg.kanidmHost} = { };
  security.acme.certs.${cfg.netbirdHost} = { };
}
