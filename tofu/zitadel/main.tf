# Phase 2: provision NetBird's identity content in Zitadel and deliver the
# generated client ids/secret to the Tier-0 box.
#
# The host's FirstInstance step (nix/zitadel) created the org, the admin human,
# and one IAM_OWNER machine user whose PAT we authenticate with here. Everything
# dynamic — the NetBird project, the two OIDC apps, the idp-mgmt service user,
# roles, and the roles->groups action — lives in this module, NOT on-box.
#
# NOTE: several resource attribute names below are version-sensitive against the
# zitadel/zitadel provider and Zitadel 2.71.7. Run `tofu validate` / a real plan
# and adjust enum strings (grant/app/auth-method types, flow/trigger types) as
# needed — these are flagged in DESIGN/NOTES as first-deploy verification items.

# Read the bootstrap PAT live over SSH (no cross-module state coupling).
data "external" "bootstrap_pat" {
  program = ["bash", "${path.module}/read-pat.sh"]
  query = {
    host = var.zitadel_domain
    user = var.ssh_user
  }
}

provider "zitadel" {
  domain   = var.zitadel_domain
  insecure = false
  port     = "443"
  # access_token = the PAT value; `token` is deprecated and expects a JWT-key
  # file path (it tries to stat the value as a path).
  access_token = data.external.bootstrap_pat.result.pat
}

# The org created by FirstInstance (looked up by name → id).
data "zitadel_orgs" "infra" {
  name        = var.org_name
  name_method = "TEXT_QUERY_METHOD_EQUALS"
}

locals {
  org_id = tolist(data.zitadel_orgs.infra.ids)[0]
}

# Login policy for the infra org: no self-service registration, MFA required.
# Overrides the instance default (which allows registration and doesn't force
# MFA). All other values carried over from the current default unchanged.
resource "zitadel_login_policy" "infra" {
  org_id = local.org_id

  allow_register = false # users come from the admin / NetBird IdP, not signup
  force_mfa      = true  # require a second factor on every interactive login

  user_login               = true
  allow_external_idp       = true
  force_mfa_local_only     = false
  passwordless_type        = "PASSWORDLESS_TYPE_ALLOWED"
  hide_password_reset      = false
  ignore_unknown_usernames = false
  allow_domain_discovery   = true
  disable_login_with_email = false
  disable_login_with_phone = false
  default_redirect_uri     = ""

  password_check_lifetime       = "240h0m0s"
  external_login_check_lifetime = "240h0m0s"
  mfa_init_skip_lifetime        = "720h0m0s"
  second_factor_check_lifetime  = "18h0m0s"
  multi_factor_check_lifetime   = "12h0m0s"

  second_factors = ["SECOND_FACTOR_TYPE_OTP", "SECOND_FACTOR_TYPE_U2F"]
  multi_factors  = ["MULTI_FACTOR_TYPE_U2F_WITH_VERIFICATION"]
}

resource "zitadel_project" "netbird" {
  org_id                 = local.org_id
  name                   = "NetBird"
  project_role_assertion = true # assert project roles into tokens (for groups)
  project_role_check     = false
}

# Role that maps to NetBird's admin group via the groups action below.
resource "zitadel_project_role" "admin" {
  org_id       = local.org_id
  project_id   = zitadel_project.netbird.id
  role_key     = "netbird_admin"
  display_name = "NetBird Admin"
}

# Dashboard SPA: PKCE public, browser SSO.
resource "zitadel_application_oidc" "dashboard" {
  org_id     = local.org_id
  project_id = zitadel_project.netbird.id
  name       = "netbird-dashboard"

  redirect_uris = [
    "https://${var.netbird_domain}/auth",
    "https://${var.netbird_domain}/silent-auth",
  ]
  post_logout_redirect_uris = ["https://${var.netbird_domain}/"]

  response_types              = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types                 = ["OIDC_GRANT_TYPE_AUTHORIZATION_CODE", "OIDC_GRANT_TYPE_REFRESH_TOKEN"]
  app_type                    = "OIDC_APP_TYPE_USER_AGENT"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_NONE" # PKCE, no secret
  version                     = "OIDC_VERSION_1_0"
  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = true
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
  dev_mode                    = false
}

# CLI / desktop: PKCE public + device-code grant — the RFC 8628 flow that is the
# whole point of moving off kanidm (headless / SSH enrollment, no setup key).
resource "zitadel_application_oidc" "cli" {
  org_id     = local.org_id
  project_id = zitadel_project.netbird.id
  name       = "netbird-cli"

  redirect_uris = [
    "http://localhost:53000/",
    "http://localhost:54000/",
  ]

  response_types = ["OIDC_RESPONSE_TYPE_CODE"]
  grant_types = [
    "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
    "OIDC_GRANT_TYPE_REFRESH_TOKEN",
    "OIDC_GRANT_TYPE_DEVICE_CODE",
  ]
  app_type                    = "OIDC_APP_TYPE_NATIVE"
  auth_method_type            = "OIDC_AUTH_METHOD_TYPE_NONE"
  version                     = "OIDC_VERSION_1_0"
  access_token_type           = "OIDC_TOKEN_TYPE_BEARER"
  access_token_role_assertion = true
  id_token_role_assertion     = true
  id_token_userinfo_assertion = true
  dev_mode                    = false
}

# Service user NetBird's IdP manager authenticates as (client_credentials).
resource "zitadel_machine_user" "idp" {
  org_id      = local.org_id
  user_name   = "netbird-idp"
  name        = "NetBird IdP manager"
  description = "client_credentials user for NetBird user sync"
  with_secret = true # exports client_id / client_secret
  # NetBird's Zitadel IdP manager parses the service-user access token AS a JWT
  # (splits on "."), so it must be JWT, not an opaque bearer token, or it panics.
  access_token_type = "ACCESS_TOKEN_TYPE_JWT"
}

# NetBird needs to create/manage users in the org.
resource "zitadel_org_member" "idp_user_manager" {
  org_id  = local.org_id
  user_id = zitadel_machine_user.idp.id
  roles   = ["ORG_USER_MANAGER"]
}

# Flatten the user's project roles into a flat `groups` claim that NetBird's JWT
# group-sync reads. Attached to the token-customisation flow below.
resource "zitadel_action" "groups_claim" {
  org_id          = local.org_id
  name            = "netbirdGroups"
  timeout         = "10s"
  allowed_to_fail = true

  script = <<-EOT
    function netbirdGroups(ctx, api) {
      if (ctx.v1.user.grants === undefined || ctx.v1.user.grants.count == 0) {
        return;
      }
      let groups = [];
      ctx.v1.user.grants.grants.forEach(grant => {
        grant.roles.forEach(role => groups.push(role));
      });
      api.v1.claims.setClaim('groups', groups);
    }
  EOT
}

resource "zitadel_trigger_actions" "access_token" {
  org_id       = local.org_id
  flow_type    = "FLOW_TYPE_CUSTOMISE_TOKEN"
  trigger_type = "TRIGGER_TYPE_PRE_ACCESS_TOKEN_CREATION"
  action_ids   = [zitadel_action.groups_claim.id]
}

resource "zitadel_trigger_actions" "id_token" {
  org_id       = local.org_id
  flow_type    = "FLOW_TYPE_CUSTOMISE_TOKEN"
  trigger_type = "TRIGGER_TYPE_PRE_USERINFO_CREATION"
  action_ids   = [zitadel_action.groups_claim.id]
}

# Deliver the four generated values to /var/lib/netbird-oidc on the box (the dir
# is created by systemd.tmpfiles in nix/netbird), then bounce the consumers.
# File provisioners ship the secret over sftp rather than a logged command line.
resource "null_resource" "deliver_oidc" {
  triggers = {
    dashboard_client_id = zitadel_application_oidc.dashboard.client_id
    cli_client_id       = zitadel_application_oidc.cli.client_id
    idp_client_id       = zitadel_machine_user.idp.client_id
    idp_client_secret   = zitadel_machine_user.idp.client_secret
    audience            = zitadel_project.netbird.id
  }

  connection {
    type  = "ssh"
    host  = var.zitadel_domain
    user  = var.ssh_user
    agent = true
  }

  provisioner "file" {
    content     = zitadel_application_oidc.dashboard.client_id
    destination = "/var/lib/netbird-oidc/dashboard-client-id"
  }
  provisioner "file" {
    content     = zitadel_application_oidc.cli.client_id
    destination = "/var/lib/netbird-oidc/cli-client-id"
  }
  provisioner "file" {
    content     = zitadel_machine_user.idp.client_id
    destination = "/var/lib/netbird-oidc/idp-client-id"
  }
  provisioner "file" {
    content     = zitadel_machine_user.idp.client_secret
    destination = "/var/lib/netbird-oidc/idp-client-secret"
  }
  # The project id is in every token's `aud` (dashboard AND cli/device), so it is
  # the shared audience the management API validates against. Per-app client ids
  # would only match one flow's tokens.
  provisioner "file" {
    content     = zitadel_project.netbird.id
    destination = "/var/lib/netbird-oidc/audience"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0400 /var/lib/netbird-oidc/idp-client-secret",
      "chmod 0444 /var/lib/netbird-oidc/cli-client-id /var/lib/netbird-oidc/dashboard-client-id /var/lib/netbird-oidc/idp-client-id /var/lib/netbird-oidc/audience",
      "systemctl restart netbird-management netbird-dashboard-render",
    ]
  }
}
