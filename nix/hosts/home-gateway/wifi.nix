{ config, lib, ... }:
let
  ssids = [
    "CasaGooch5"
    "CasaGooch4"
  ];
  pskName = ssid: "wifi-psk-${lib.toLower ssid}";
in
{
  sops.secrets = lib.genAttrs (map pskName ssids) (_: { });
  sops.templates."wireless.conf" = {
    owner = "wpa_supplicant";
    content = lib.concatMapStrings (
      ssid: "${pskName ssid}=${config.sops.placeholder.${pskName ssid}}\n"
    ) ssids;
    restartUnits = [ "wpa_supplicant-wlan0.service" ];
  };

  networking.wireless = {
    enable = true;
    interfaces = [ "wlan0" ];
    secretsFile = config.sops.templates."wireless.conf".path;
    extraConfig = "country=NL";
    networks = lib.genAttrs ssids (ssid: {
      authProtocols = [ "WPA-PSK" ];
      pskRaw = "ext:${pskName ssid}";
    });
  };

  boot.extraModprobeConfig = ''
    options brcmfmac roamoff=1
  '';
}
