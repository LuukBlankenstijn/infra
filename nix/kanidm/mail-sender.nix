# kanidm-mail-sender: external dispatcher for the kanidm message queue.
# Reads queued messages from the kanidm DB (auth via SA token) and ships them
# via SMTP. Without this running, kanidm's "send recovery email" path is a
# no-op (the message just sits in the queue).
{
  config,
  pkgs,
  cfg,
  ...
}:
let
  clientConfig = pkgs.writeText "kanidm-client-config" ''
    uri = "https://${cfg.kanidmHost}"
    verify_ca = true
    verify_hostnames = true
    ca_path = "/etc/ssl/certs/ca-certificates.crt"
  '';

  runtimeConfig = "/run/kanidm-mail-sender/config.toml";
in
{
  users.users.kanidm-mail-sender = {
    isSystemUser = true;
    group = "kanidm-mail-sender";
    description = "Kanidm mail dispatcher service user";
  };
  users.groups.kanidm-mail-sender = { };

  systemd.services.kanidm-mail-sender = {
    description = "Kanidm outbound mail dispatcher";
    after = [
      "network-online.target"
      "kanidm.service"
      "kanidm-bootstrap-reconciler.service"
    ];
    wants = [ "network-online.target" ];
    requires = [
      "kanidm-bootstrap-reconciler.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "exec";
      Restart = "on-failure";
      RestartSec = "30s";
      User = "kanidm-mail-sender";
      Group = "kanidm-mail-sender";
      RuntimeDirectory = "kanidm-mail-sender";
      RuntimeDirectoryMode = "0700";
    };

    # Template the mail-sender config at preStart so the SA token + SMTP
    # password never land in /nix/store. Both come from runtime files (one
    # from bootstrap, one from sops).
    preStart = ''
      token=$(cat /var/lib/kanidm-mail-sender/token)
      pw=$(cat ${config.sops.secrets."kanidm/smtp-password".path})
      umask 077
      cat > ${runtimeConfig} <<EOF
      token = "$token"
      schedule = "0/5 * * * * *"
      instance_display_name = "kanidm @ ${cfg.kanidmHost}"
      instance_url = "https://${cfg.kanidmHost}"
      mail_from_address = "auth@${cfg.domain}"
      mail_reply_to_address = "auth@${cfg.domain}"
      mail_relay = "smtp.protonmail.ch"
      mail_username = "${cfg.mailUsername}"
      mail_password = "$pw"
      mail_connect_timeout_seconds = 15
      EOF
    '';

    script = ''
      exec ${config.services.kanidm.package}/bin/kanidm-mail-sender \
        --client-config ${clientConfig} \
        --mail-sender-config ${runtimeConfig}
    '';
  };

  sops.secrets."kanidm/smtp-password" = {
    owner = "kanidm-mail-sender";
    mode = "0400";
    restartUnits = [ "kanidm-mail-sender.service" ];
  };
}
