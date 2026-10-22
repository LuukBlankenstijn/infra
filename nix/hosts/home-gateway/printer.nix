{
  config,
  lib,
  pkgs,
  ...
}:
let
  net = import ./printer-network.nix;
  privateRanges = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "100.64.0.0/10"
  ];

  setup = pkgs.writeShellApplication {
    name = "printer-ap-setup";
    runtimeInputs = [
      pkgs.iw
      pkgs.iproute2
      pkgs.gawk
    ];
    text = ''
      channel=$(iw dev wlan0 info | awk '$1 == "channel" { print $2 }')
      freq=$(iw dev wlan0 info | awk '$1 == "channel" { print substr($3, 2) }')
      if [ -z "$channel" ] || [ -z "$freq" ]; then
        echo "wlan0 is not associated; uap0 has no channel to share" >&2
        exit 1
      fi
      mode=a
      if [ "$freq" -lt 3000 ]; then
        mode=g
      fi

      mac=$(cat /sys/class/net/wlan0/address)
      ap_mac=$(printf '%02x:%s:%02x' \
        "$(( 0x''${mac%%:*} | 0x02 ))" \
        "$(echo "$mac" | cut -d: -f2-5)" \
        "$(( (0x''${mac##*:} + 2) % 256 ))")

      iw dev uap0 info >/dev/null 2>&1 || iw dev wlan0 interface add uap0 type __ap
      ip link set uap0 address "$ap_mac"
      ip address replace ${net.gateway}/${toString net.prefixLength} dev uap0

      umask 077
      cat > /run/printer-ap/hostapd.conf <<EOF
      interface=uap0
      driver=nl80211
      ssid=${net.ssid}
      country_code=NL
      ieee80211d=1
      hw_mode=$mode
      channel=$channel
      ieee80211n=1
      wmm_enabled=1
      auth_algs=1
      wpa=2
      wpa_key_mgmt=WPA-PSK
      rsn_pairwise=CCMP
      wpa_passphrase=$(cat "$CREDENTIALS_DIRECTORY/psk")
      EOF
    '';
  };

  watch = pkgs.writeShellApplication {
    name = "printer-ap-watch";
    runtimeInputs = [
      pkgs.iw
      pkgs.iproute2
      pkgs.iputils
      pkgs.gawk
      config.systemd.package
    ];
    text = ''
      failures_file=/run/printer-ap-watch/uplink-failures
      gateway=$(ip -4 route show default dev wlan0 | awk '{ print $3; exit }')
      if [ -z "$gateway" ] || ! ping -I wlan0 -c 3 -W 3 "$gateway" >/dev/null; then
        failures=$(( $(cat "$failures_file" 2>/dev/null || echo 0) + 1 ))
        echo "$failures" > "$failures_file"
        echo "uplink check failed, $failures in a row"
        if [ "$failures" -ge 3 ]; then
          echo "restarting wpa_supplicant-wlan0 and with it printer-ap"
          systemctl restart wpa_supplicant-wlan0.service
          echo 0 > "$failures_file"
        fi
        exit 0
      fi
      echo 0 > "$failures_file"

      uplink_channel=$(iw dev wlan0 info | awk '$1 == "channel" { print $2 }')
      ap_channel=$(iw dev uap0 info 2>/dev/null | awk '$1 == "channel" { print $2 }')
      if ! systemctl is-active --quiet printer-ap.service || [ "$ap_channel" != "$uplink_channel" ]; then
        echo "restarting printer-ap: uap0 on channel '$ap_channel', wlan0 on channel '$uplink_channel'"
        systemctl restart printer-ap.service
      fi
    '';
  };
in
{
  sops.secrets.printer-wifi-psk = { };

  systemd.services.printer-ap = {
    description = "Access point uap0 for the 3D printer, on wlan0's channel";
    wantedBy = [ "multi-user.target" ];
    after = [ "wpa_supplicant-wlan0.service" ];
    partOf = [ "wpa_supplicant-wlan0.service" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      RuntimeDirectory = "printer-ap";
      RuntimeDirectoryMode = "0700";
      LoadCredential = "psk:${config.sops.secrets.printer-wifi-psk.path}";
      ExecStartPre = lib.getExe setup;
      ExecStart = "${pkgs.hostapd}/bin/hostapd /run/printer-ap/hostapd.conf";
      ExecStopPost = "-${pkgs.iw}/bin/iw dev uap0 del";
      Restart = "always";
      RestartSec = 10;
    };
  };

  systemd.services.printer-ap-watch = {
    description = "Recover wlan0 and keep uap0 on wlan0's channel";
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "printer-ap-watch";
      RuntimeDirectoryPreserve = true;
      ExecStart = lib.getExe watch;
    };
  };

  systemd.timers.printer-ap-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
    };
  };

  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;
    settings = {
      port = 0;
      interface = "uap0";
      bind-dynamic = true;
      dhcp-authoritative = true;
      dhcp-range = "${net.printer},${net.printer},12h";
      dhcp-option = [
        "option:router,${net.gateway}"
        "option:dns-server,1.1.1.1,9.9.9.9"
      ];
    };
  };

  networking.dhcpcd.denyInterfaces = [ "uap0" ];

  networking.nat = {
    enable = true;
    internalInterfaces = [ "uap0" ];
    externalInterface = "wlan0";
  };

  networking.firewall = {
    interfaces.uap0.allowedUDPPorts = [ 67 ];
    extraCommands = ''
      iptables -N printer-forward 2>/dev/null || iptables -F printer-forward
      iptables -A printer-forward -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
      ${lib.concatMapStrings (range: ''
        iptables -A printer-forward -d ${range} -j DROP
      '') privateRanges}
      iptables -C FORWARD -i uap0 -j printer-forward 2>/dev/null || iptables -I FORWARD -i uap0 -j printer-forward
    '';
    extraStopCommands = ''
      iptables -D FORWARD -i uap0 -j printer-forward 2>/dev/null || true
      iptables -F printer-forward 2>/dev/null || true
      iptables -X printer-forward 2>/dev/null || true
    '';
  };
}
