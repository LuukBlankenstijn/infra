{ config, ... }:
let
  controlPort = 7000;
  forwardedTcpPorts = [
    80
    443
  ];
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
      bindPort = controlPort;
      auth = {
        method = "token";
        token = "{{ .Envs.FRP_TOKEN }}";
      };
      transport.tls.force = true;
      allowPorts = map (port: { single = port; }) forwardedTcpPorts;
    };
  };

  networking.firewall.allowedTCPPorts = [ controlPort ] ++ forwardedTcpPorts;
}
