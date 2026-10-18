{ config, ... }:
let
  tls = config.cfg.deviceCert;
in
{
  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      mqtt = {
        server = "mqtts://mqtt.luukblankenstijn.nl:443";
        cert = tls.certFile;
        key = tls.keyFile;
      };
      serial = {
        port = "/dev/serial/by-id/usb-SONOFF_SONOFF_Dongle_Plus_MG24_6224ff2e9a8cf01184592cb9d9065118-if00-port0";
        adapter = "ember";
        baudrate = 115200;
      };
      frontend = {
        enabled = true;
        host = "127.0.0.1";
        port = 8080;
      };
      devices."0x001788010dc3e925".friendly_name = "roof-lamp";
    };
  };

  systemd.services.zigbee2mqtt = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig.SupplementaryGroups = [ tls.group ];
  };

  systemd.paths.zigbee2mqtt-device-cert = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = tls.certFile;
  };

  systemd.services.zigbee2mqtt-device-cert = {
    description = "Restart zigbee2mqtt so it connects with the renewed device certificate";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.systemd.package}/bin/systemctl try-restart zigbee2mqtt.service";
    };
  };
}
