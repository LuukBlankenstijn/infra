{ config, ... }:
let
  ports = builtins.fromJSON (builtins.readFile ./ports.json);
in
{
  sops.secrets.frp-token = { };
  sops.templates."frps.env" = {
    content = ''
      FRP_TOKEN=${config.sops.placeholder.frp-token}
    '';
    restartUnits = [ "frp-edge.service" ];
  };

  services.frp.instances.edge = {
    enable = true;
    role = "server";
    environmentFiles = [ config.sops.templates."frps.env".path ];
    settings = {
      bindPort = ports.frpControl;
      auth = {
        method = "token";
        token = "{{ .Envs.FRP_TOKEN }}";
      };
      transport.tls.force = true;
      allowPorts = map (port: { single = port; }) (ports.forwardedTcp ++ ports.forwardedUdp);
      enablePrometheus = true;
      webServer = {
        addr = "127.0.0.1";
        port = 7500;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ ports.frpControl ] ++ ports.forwardedTcp;
  networking.firewall.allowedUDPPorts = ports.forwardedUdp;
}
