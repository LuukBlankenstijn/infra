locals {
  netbird_host = "netbird.luukblankenstijn.nl"
}

data "authentik_flow" "implicit_consent" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_certificate_key_pair" "self_signed" {
  name = "authentik Self-signed Certificate"
}

data "authentik_property_mapping_provider_scope" "oidc" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
  ]
}

resource "random_password" "netbird_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "netbird" {
  name               = "NetBird"
  client_id          = "netbird"
  client_secret      = random_password.netbird_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.implicit_consent.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = data.authentik_certificate_key_pair.self_signed.id
  property_mappings  = data.authentik_property_mapping_provider_scope.oidc.ids

  include_claims_in_id_token = true
  grant_types                = ["authorization_code", "refresh_token"]

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.netbird_host}/oauth2/callback"
    },
    {
      matching_mode = "strict"
      url           = "https://${local.netbird_host}/oauth2/logout/callback"
    },
  ]
}

resource "authentik_application" "netbird" {
  name              = "NetBird"
  slug              = "netbird"
  protocol_provider = authentik_provider_oauth2.netbird.id
  meta_launch_url   = "https://${local.netbird_host}"
}

resource "authentik_policy_binding" "netbird_admins" {
  target = authentik_application.netbird.uuid
  group  = authentik_group.infra_admins.id
  order  = 0
}

resource "vault_mount" "authentik" {
  path        = "authentik"
  type        = "kv-v2"
  description = "Authentik OIDC client credentials, one path per consumer."
}

resource "vault_kv_secret_v2" "netbird" {
  mount = vault_mount.authentik.path
  name  = "netbird/netbird"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.netbird.client_id
    client_secret = random_password.netbird_client_secret.result
    issuer        = "${var.authentik_url}/application/o/${authentik_application.netbird.slug}/"
  })
}
