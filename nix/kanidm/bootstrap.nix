{
  config,
  pkgs,
  cfg,
  ...
}:
let
  tokenFile = "/var/lib/kanidm/reconciler-token";
  mailTokenFile = "/var/lib/kanidm-mail-sender/token";
in
{
  systemd.services.kanidm-bootstrap-reconciler = {
    description = "Mint kanidm SA token for the external reconciler";
    after = [ "kanidm.service" ];
    requires = [ "kanidm.service" ];
    wantedBy = [ "multi-user.target" ];

    path = [
      config.services.kanidm.package
      pkgs.jq
      pkgs.curl
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
    };

    environment = {
      KANIDM_URL = "https://${cfg.kanidmHost}";
      KANIDM_CA_PATH = "/etc/ssl/certs/ca-certificates.crt";
    };

    # Two logins on purpose:
    #   - admin (system_admins) holds the privilege boundary for high-priv
    #     groups like idm_oauth2_client_admins.
    #   - idm_admin handles day-to-day IDM ops: create the SA, add to the
    #     people/group admin groups, mint the token.
    # The token's `.result` field (not `.secret`) carries the bearer string
    # in 1.10's --output json.
    script = ''
      set -euo pipefail

      # Each block has its own guard so that adding new tokens later doesn't
      # require nuking existing ones. Bootstrap is fully idempotent.

      for i in $(seq 1 60); do
        curl --silent --fail "$KANIDM_URL/status" >/dev/null && break
        sleep 1
      done

      # --- Step 1: reconciler SA + token (idm_admin then admin) -----------
      if [ ! -s ${tokenFile} ]; then
        export KANIDM_PASSWORD
        KANIDM_PASSWORD="$(cat ${config.sops.secrets."kanidm/idm-admin-password".path})"
        kanidm login --name idm_admin

        if ! kanidm service-account get infra-reconciler --name idm_admin >/dev/null 2>&1; then
          kanidm service-account create infra-reconciler \
            "External reconciler service account" \
            idm_service_account_admins \
            --name idm_admin
        fi

        for g in idm_people_admins idm_group_admins; do
          kanidm group add-members "$g" infra-reconciler --name idm_admin || true
        done

        token=$(kanidm service-account api-token generate \
                  infra-reconciler "tofu provider" \
                  --readwrite --name idm_admin --output json | jq -r .result)

        kanidm logout --name idm_admin || true

        # high-priv group needs the system admin
        KANIDM_PASSWORD="$(cat ${config.sops.secrets."kanidm/admin-password".path})"
        kanidm login --name admin
        kanidm group add-members idm_oauth2_client_admins infra-reconciler --name admin || true
        kanidm logout --name admin || true

        umask 077
        mkdir -p "$(dirname ${tokenFile})"
        printf '%s' "$token" > ${tokenFile}
        chmod 0400 ${tokenFile}
      fi

      # --- Step 2: mail-sender SA + token (idm_admin) -------------------
      if [ ! -s ${mailTokenFile} ]; then
        export KANIDM_PASSWORD
        KANIDM_PASSWORD="$(cat ${config.sops.secrets."kanidm/idm-admin-password".path})"
        kanidm login --name idm_admin

        if ! kanidm service-account get kanidm-mail-sender --name idm_admin >/dev/null 2>&1; then
          kanidm service-account create kanidm-mail-sender \
            "Outbound mail dispatcher" \
            idm_service_account_admins \
            --name idm_admin
        fi
        kanidm group add-members idm_message_senders kanidm-mail-sender --name idm_admin || true

        mailToken=$(kanidm service-account api-token generate \
                      kanidm-mail-sender "mail-sender" \
                      --readwrite --name idm_admin --output json | jq -r .result)

        kanidm logout --name idm_admin || true

        install -d -o kanidm-mail-sender -g kanidm-mail-sender -m 0700 \
          "$(dirname ${mailTokenFile})"
        umask 077
        printf '%s' "$mailToken" > ${mailTokenFile}
      fi

      # Re-assert ownership every boot so the mail-sender user (which may
      # have been created after the first token mint) can read it.
      install -d -o kanidm-mail-sender -g kanidm-mail-sender -m 0700 \
        "$(dirname ${mailTokenFile})"
      chown kanidm-mail-sender:kanidm-mail-sender ${mailTokenFile}
      chmod 0400 ${mailTokenFile}
    '';
  };
}
