{ config, pkgs, ... }:
let
  tls = config.cfg.deviceCert;
  check = pkgs.writeShellApplication {
    name = "home-heartbeat-check";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      token="$(cat "$CREDENTIALS_DIRECTORY/token")"
      topic="$(cat "$CREDENTIALS_DIRECTORY/topic")"
      state="$STATE_DIRECTORY/down"

      if beats="$(curl --silent --fail --max-time 30 \
          --cert ${tls.certFile} --key ${tls.keyFile} \
          --header "Authorization: Bearer $token" \
          "https://ntfy.luukblankenstijn.nl/heartbeat/json?poll=1&since=10m")" \
        && [ -n "$beats" ]; then
        if [ -e "$state" ]; then
          curl --silent --fail --max-time 30 \
            --header "Title: Home alerting is back" \
            --header "Priority: 3" \
            --header "Tags: white_check_mark" \
            --data "The cluster's Alertmanager reaches ntfy again (down since $(cat "$state"))." \
            "https://ntfy.sh/$topic" >/dev/null
          rm "$state"
        fi
        exit 0
      fi

      if [ ! -e "$state" ]; then
        curl --silent --fail --max-time 30 \
          --header "Title: Home alerting is down" \
          --header "Priority: 5" \
          --header "Tags: rotating_light" \
          --data "No Watchdog heartbeat reached ntfy.luukblankenstijn.nl in 10 minutes. home-server, the home internet, the frp tunnel, Mimir's Alertmanager or ntfy is down; alerts from home are not being delivered." \
          "https://ntfy.sh/$topic" >/dev/null
        date --iso-8601=minutes > "$state"
      fi
    '';
  };
in
{
  sops.secrets."ntfy-heartbeat-token" = { };
  sops.secrets."outside-alert-topic" = { };

  systemd.services.home-heartbeat-check = {
    description = "Alert on public ntfy.sh when the home Watchdog heartbeat stops";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${check}/bin/home-heartbeat-check";
      DynamicUser = true;
      SupplementaryGroups = [ tls.group ];
      StateDirectory = "home-heartbeat";
      LoadCredential = [
        "token:${config.sops.secrets."ntfy-heartbeat-token".path}"
        "topic:${config.sops.secrets."outside-alert-topic".path}"
      ];
    };
  };

  systemd.timers.home-heartbeat-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10m";
      OnUnitActiveSec = "5m";
    };
  };
}
