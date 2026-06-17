# Zitadel IdP — replaces kanidm. Provides the OAuth2 device authorization grant
# (RFC 8628) NetBird needs for headless / SSH peer enrollment.
#
# Tier 0 owns only the bootstrap-critical state here: Postgres, the Zitadel
# service, and a declarative FirstInstance (org + admin human + one IAM_OWNER
# machine user whose PAT the external tofu/zitadel module authenticates with to
# provision the NetBird project/apps). Everything dynamic (OIDC clients, the
# idp-mgmt service user, roles) is created by tofu, NOT on-box.
{
  config,
  pkgs,
  lib,
  cfg,
  ...
}:
let
  nameParts = lib.splitString " " cfg.adminUser.legalName;
  firstName = lib.head nameParts;
  lastName = lib.concatStringsSep " " (lib.tail nameParts);
in
{
  # Zitadel's encrypted data is in Postgres; its state dir holds only the
  # bootstrap PAT. Postgres uses peer auth over the unix socket — no DB
  # password ever lands in the Nix store.
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ "zitadel" ];
    ensureUsers = [
      {
        name = "zitadel";
        ensureDBOwnership = true;
        # Zitadel's init connects as this role (Admin) and runs CREATE ROLE /
        # CREATE DATABASE, so it needs both privileges, not just ownership.
        ensureClauses = {
          createdb = true;
          createrole = true;
        };
      }
    ];
  };

  services.zitadel = {
    enable = true;
    # External TLS: Traefik terminates HTTPS and forwards h2c to :8080.
    tlsMode = "external";
    masterKeyFile = config.sops.secrets."zitadel/masterkey".path;

    settings = {
      # 8080 is taken by the netbird dashboard nginx; keep zitadel off it.
      Port = 8081;
      ExternalDomain = cfg.zitadelHost;
      ExternalPort = 443;
      ExternalSecure = true;

      # Zitadel's sonyflake ID generator needs to identify the machine. Its
      # defaults (private-IP + a Google-metadata webhook) both fail on a Hetzner
      # box with no private IP and no GCP metadata → panic in the
      # 03_default_instance setup migration. Identify by hostname instead.
      Machine.Identification = {
        PrivateIp.Enabled = false;
        Hostname.Enabled = true;
        Webhook.Enabled = false;
      };

      Database.postgres = {
        Host = "/run/postgresql";
        Port = 5432;
        Database = "zitadel";
        User = {
          Username = "zitadel";
          SSL.Mode = "disable";
        };
        Admin = {
          Username = "zitadel";
          ExistingDatabase = "zitadel";
          SSL.Mode = "disable";
        };
      };
    };

    # FirstInstance is processed once (tracked in Postgres). On a fresh DB it
    # creates the org, the admin human, and the bootstrap machine user, writing
    # that user's PAT to PatPath for tofu to read.
    steps.FirstInstance = {
      InstanceName = "Tier0";
      Org = {
        Name = "infra";
        Human = {
          UserName = cfg.adminUser.name;
          FirstName = firstName;
          LastName = lastName;
          Email = {
            Address = lib.head cfg.adminUser.mailAddresses;
            Verified = true;
          };
          PasswordChangeRequired = false;
        };
        Machine = {
          Machine = {
            Username = "tier0-bootstrap";
            Name = "Tier0 bootstrap";
          };
          Pat.ExpirationDate = "2999-01-01T00:00:00Z";
        };
      };
      PatPath = "/var/lib/zitadel/bootstrap-pat";
    };

    # Secret-bearing config kept out of the Nix store via sops templates,
    # merged in through the module's extra*Paths (last file wins).
    extraSettingsPaths = [ config.sops.templates."zitadel-smtp.yaml".path ];
    extraStepsPaths = [ config.sops.templates."zitadel-firstinstance.yaml".path ];
  };

  systemd.services.zitadel = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    # PatPath lives under this dir; persist it alongside Postgres (impermanence).
    serviceConfig.StateDirectory = "zitadel";
  };

  sops.secrets."zitadel/masterkey" = {
    owner = "zitadel";
    restartUnits = [ "zitadel.service" ];
  };
  sops.secrets."zitadel/admin-password" = { };
  sops.secrets."zitadel/smtp-password" = { };

  # Native SMTP (DefaultInstance lives in the runtime config, not steps).
  # Protonmail submission: STARTTLS on 587.
  sops.templates."zitadel-smtp.yaml" = {
    owner = "zitadel";
    restartUnits = [ "zitadel.service" ];
    content = ''
      DefaultInstance:
        SMTPConfiguration:
          SMTP:
            Host: "smtp.protonmail.ch:587"
            User: "${cfg.mailUsername}"
            Password: "${config.sops.placeholder."zitadel/smtp-password"}"
          TLS: true
          From: "${cfg.mailUsername}"
          FromName: "ZITADEL"
          ReplyToAddress: "${cfg.mailUsername}"
    '';
  };

  # Admin human password (FirstInstance lives in steps).
  sops.templates."zitadel-firstinstance.yaml" = {
    owner = "zitadel";
    restartUnits = [ "zitadel.service" ];
    content = ''
      FirstInstance:
        Org:
          Human:
            Password: "${config.sops.placeholder."zitadel/admin-password"}"
    '';
  };
}
