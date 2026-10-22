{ config, lib, ... }:
let
  printer = (import ./printer-network.nix).printer;
  targets = {
    zigbee2mqtt = {
      localIP = "127.0.0.1";
      localPort = config.services.zigbee2mqtt.settings.frontend.port;
    };
    printer-mqtt = {
      localIP = printer;
      localPort = 1883;
    };
    printer-upload = {
      localIP = printer;
      localPort = 80;
    };
    printer-camera = {
      localIP = printer;
      localPort = 8080;
    };
  };
  proxies = lib.concatLists (
    lib.mapAttrsToList (name: target: [
      (
        target
        // {
          inherit name;
          type = "stcp";
          secretKey = "{{ .Envs.PI_TUNNEL_SECRET_KEY }}";
        }
      )
      (
        target
        // {
          name = "${name}-p2p";
          type = "xtcp";
          secretKey = "{{ .Envs.PI_TUNNEL_SECRET_KEY }}";
        }
      )
    ]) targets
  );
in
{
  sops.secrets.frp-token = { };
  sops.secrets.pi-tunnel-secret-key = { };
  sops.templates."frpc.env" = {
    content = ''
      FRP_TOKEN=${config.sops.placeholder.frp-token}
      PI_TUNNEL_SECRET_KEY=${config.sops.placeholder.pi-tunnel-secret-key}
    '';
    restartUnits = [ "frp-pi-tunnel.service" ];
  };

  services.frp.instances.pi-tunnel = {
    enable = true;
    role = "client";
    environmentFiles = [ config.sops.templates."frpc.env".path ];
    settings = {
      serverAddr = "hertzner.luukblankenstijn.nl";
      serverPort = 7000;
      loginFailExit = false;
      auth = {
        method = "token";
        token = "{{ .Envs.FRP_TOKEN }}";
      };
      transport.tls.enable = true;
      natHoleStunServer = "stun.easyvoip.com:3478";
      inherit proxies;
    };
  };
}
