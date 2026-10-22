locals {
  pingvin_share_host = "share.luukblankenstijn.nl"
}

data "authentik_property_mapping_provider_scope" "openid_profile" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

resource "authentik_property_mapping_provider_scope" "email_verified" {
  name        = "Pingvin Share: email, verified"
  scope_name  = "email"
  description = "Email address"
  expression  = "return {\"email\": request.user.email, \"email_verified\": True}"
}

resource "random_password" "pingvin_share_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "pingvin_share" {
  name               = "Pingvin Share"
  client_id          = "pingvin-share"
  client_secret      = random_password.pingvin_share_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.implicit_consent.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = data.authentik_certificate_key_pair.self_signed.id
  property_mappings = concat(
    data.authentik_property_mapping_provider_scope.openid_profile.ids,
    [authentik_property_mapping_provider_scope.email_verified.id],
  )

  include_claims_in_id_token = true
  grant_types                = ["authorization_code"]

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.pingvin_share_host}/api/oauth/callback/oidc"
    },
  ]
}

resource "authentik_application" "pingvin_share" {
  name              = "Pingvin Share"
  slug              = "pingvin-share"
  protocol_provider = authentik_provider_oauth2.pingvin_share.id
  meta_launch_url   = "https://${local.pingvin_share_host}"
}

resource "authentik_policy_binding" "pingvin_share_admins" {
  target = authentik_application.pingvin_share.uuid
  group  = authentik_group.infra_admins.id
  order  = 0
}

resource "vault_kv_secret_v2" "pingvin_share" {
  mount = vault_mount.authentik.path
  name  = "pingvin-share/pingvin-share"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.pingvin_share.client_id
    client_secret = random_password.pingvin_share_client_secret.result
    issuer        = "${var.authentik_url}/application/o/${authentik_application.pingvin_share.slug}/"
  })
}

resource "vault_policy" "pingvin_share" {
  name = "authentik-pingvin-share-pingvin-share"

  policy = <<-EOT
    path "${vault_mount.authentik.path}/data/${vault_kv_secret_v2.pingvin_share.name}" {
      capabilities = ["read"]
    }

    path "${vault_mount.authentik.path}/metadata/${vault_kv_secret_v2.pingvin_share.name}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "pingvin_share" {
  backend   = "kubernetes"
  role_name = "authentik-pingvin-share"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["pingvin-share"]

  token_policies = [vault_policy.pingvin_share.name]
  token_ttl      = 3600
}
