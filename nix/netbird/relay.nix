{
  config,
  pkgs,
  cfg,
  ...
}:
let
  acmeDir = config.security.acme.certs.${cfg.netbirdHost}.directory;
  port = 33080;
in
{
  systemd.services.netbird-relay = {
    description = "NetBird relay (RFC8489-style replacement for TURN, newer peers)";

    after = [ "network-online.target" "acme-finished-${cfg.netbirdHost}.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "exec";
      Restart = "always";
      DynamicUser = false;
      User = "root";
    };

    script = ''
      export NB_AUTH_SECRET="$(cat ${config.sops.secrets."netbird/relay-auth-secret".path})"
      exec ${pkgs.netbird-relay}/bin/netbird-relay \
        --listen-address :${toString port} \
        --exposed-address rels://${cfg.netbirdHost}:${toString port} \
        --tls-cert-file ${acmeDir}/fullchain.pem \
        --tls-key-file ${acmeDir}/key.pem \
        --log-file console \
        --log-level info
    '';
  };

  sops.secrets."netbird/relay-auth-secret" = {
    restartUnits = [
      "netbird-relay.service"
      "netbird-management.service"
    ];
  };
}
