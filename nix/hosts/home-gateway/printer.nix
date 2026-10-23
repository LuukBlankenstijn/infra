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
      freq=$(iw dev wlan0 link | awk '/^Connected/ { connected = 1 } connected && $1 == "freq:" { print int($2) }')
      if [ -z "$freq" ]; then
        echo "wlan0 is not connected; uap0 has no channel to share" >&2
        exit 1
      fi
      if [ "$freq" -lt 3000 ]; then
        mode=g
        channel=$(( freq == 2484 ? 14 : (freq - 2407) / 5 ))
      else
        mode=a
        channel=$(( (freq - 5000) / 5 ))
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

  guard = pkgs.writeShellApplication {
    name = "printer-ap-guard";
    runtimeInputs = [
      pkgs.iw
      pkgs.iproute2
      pkgs.iputils
      pkgs.gawk
      pkgs.kmod
      config.systemd.package
    ];
    text = ''
      uplink_freq() {
        { iw dev wlan0 link 2>/dev/null || true; } | awk '/^Connected/ { connected = 1 } connected && $1 == "freq:" { print int($2) }'
      }

      stop_ap() {
        if systemctl is-active --quiet printer-ap.service; then
          echo "stopping printer-ap so wlan0 can scan, restarting wpa_supplicant-wlan0"
          systemctl stop printer-ap.service || true
          systemctl restart wpa_supplicant-wlan0.service || true
        fi
      }

      failures=0
      while true; do
        freq=$(uplink_freq)
        if [ -z "$freq" ]; then
          stop_ap
          failures=$(( failures + 1 ))
        else
          gateway=$({ ip -4 route show default dev wlan0 2>/dev/null || true; } | awk '{ print $3; exit }')
          if [ -n "$gateway" ] && ping -I wlan0 -c 2 -W 2 "$gateway" >/dev/null; then
            failures=0
            ap_freq=$({ iw dev uap0 info 2>/dev/null || true; } | awk '$1 == "channel" { print substr($3, 2) }')
            if ! systemctl is-active --quiet printer-ap.service || [ "$ap_freq" != "$freq" ]; then
              echo "starting printer-ap on $freq MHz (uap0 was on '$ap_freq')"
              systemctl restart printer-ap.service || true
            fi
          else
            failures=$(( failures + 1 ))
          fi
        fi

        case "$failures" in
          0) ;;
          12)
            echo "uplink down for 2 minutes: restarting wpa_supplicant-wlan0"
            stop_ap
            systemctl restart wpa_supplicant-wlan0.service || true
            ;;
          24)
            echo "uplink down for 4 minutes: reloading brcmfmac"
            stop_ap
            modprobe -r -a brcmfmac_wcc brcmfmac || true
            modprobe brcmfmac || true
            sleep 5
            systemctl restart wpa_supplicant-wlan0.service || true
            ;;
          *)
            if [ "$failures" -ge 36 ] && [ "$(awk '{ print int($1) }' /proc/uptime)" -ge 1800 ]; then
              echo "uplink down for 6 minutes: rebooting"
              systemctl reboot
            fi
            ;;
        esac
        sleep 10
      done
    '';
  };
in
{
  sops.secrets.printer-wifi-psk = { };

  systemd.services.printer-ap = {
    description = "Access point uap0 for the 3D printer, on wlan0's channel; started by printer-ap-guard";
    serviceConfig = {
      RuntimeDirectory = "printer-ap";
      RuntimeDirectoryMode = "0700";
      LoadCredential = "psk:${config.sops.secrets.printer-wifi-psk.path}";
      ExecStartPre = lib.getExe setup;
      ExecStart = "${pkgs.hostapd}/bin/hostapd /run/printer-ap/hostapd.conf";
      ExecStopPost = "-${pkgs.iw}/bin/iw dev uap0 del";
    };
  };

  systemd.services.printer-ap-guard = {
    description = "Run uap0 only while wlan0 is connected, on its channel; recover wlan0";
    wantedBy = [ "multi-user.target" ];
    after = [ "wpa_supplicant-wlan0.service" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = lib.getExe guard;
      Restart = "always";
      RestartSec = 10;
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
      dhcp-range = "${net.guestFirst},${net.guestLast},12h";
      dhcp-host = "${net.printerMac},${net.printer}";
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
