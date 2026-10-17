locals {
  openbao_admin_group = "authentik Admins"
}

resource "random_password" "openbao_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "openbao" {
  name               = "OpenBao"
  client_id          = "openbao"
  client_secret      = random_password.openbao_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.implicit_consent.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = data.authentik_certificate_key_pair.self_signed.id
  property_mappings  = data.authentik_property_mapping_provider_scope.oidc.ids
  grant_types        = ["authorization_code", "refresh_token"]

  include_claims_in_id_token = true

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "${var.bao_address}/ui/vault/auth/oidc/oidc/callback"
    },
    {
      matching_mode = "strict"
      url           = "http://localhost:8250/oidc/callback"
    },
  ]
}

resource "authentik_application" "openbao" {
  name              = "OpenBao"
  slug              = "openbao"
  protocol_provider = authentik_provider_oauth2.openbao.id
  meta_launch_url   = "${var.bao_address}/ui/vault/auth?with=oidc%2F"
}

data "authentik_group" "admins" {
  name = local.openbao_admin_group
}

resource "authentik_policy_binding" "openbao_admins" {
  target = authentik_application.openbao.uuid
  group  = data.authentik_group.admins.id
  order  = 0
}

resource "vault_policy" "operator" {
  name = "operator"

  policy = <<-EOT
    path "devices/*" {
      capabilities = ["read", "list"]
    }

    path "pki-hosts/issue/*" {
      capabilities = ["update"]
    }

    path "sys/mounts" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_jwt_auth_backend_role" "authentik" {
  backend   = "oidc"
  role_name = "authentik"
  role_type = "oidc"

  user_claim            = "preferred_username"
  groups_claim          = "groups"
  oidc_scopes           = ["openid", "profile", "email"]
  allowed_redirect_uris = [for uri in authentik_provider_oauth2.openbao.allowed_redirect_uris : uri.url]

  bound_claims = {
    groups = local.openbao_admin_group
  }

  token_policies = [vault_policy.operator.name]
  token_ttl      = 3600
}

resource "vault_generic_endpoint" "oidc_config" {
  path                 = "auth/oidc/config"
  ignore_absent_fields = true
  disable_delete       = true

  data_json = jsonencode({
    oidc_discovery_url = "${var.authentik_url}/application/o/${authentik_application.openbao.slug}/"
    bound_issuer       = "${var.authentik_url}/application/o/${authentik_application.openbao.slug}/"
    oidc_client_id     = authentik_provider_oauth2.openbao.client_id
    oidc_client_secret = random_password.openbao_client_secret.result
    default_role       = vault_jwt_auth_backend_role.authentik.role_name
  })
}
