locals {
  grafana_host = "grafana.luukblankenstijn.nl"
}

data "authentik_property_mapping_provider_scope" "offline_access" {
  managed = "goauthentik.io/providers/oauth2/scope-offline_access"
}

resource "random_password" "grafana_client_secret" {
  length  = 64
  special = false
}

resource "authentik_provider_oauth2" "grafana" {
  name               = "Grafana"
  client_id          = "grafana"
  client_secret      = random_password.grafana_client_secret.result
  client_type        = "confidential"
  authorization_flow = data.authentik_flow.implicit_consent.id
  invalidation_flow  = data.authentik_flow.invalidation.id
  signing_key        = data.authentik_certificate_key_pair.self_signed.id
  property_mappings = concat(
    data.authentik_property_mapping_provider_scope.oidc.ids,
    [data.authentik_property_mapping_provider_scope.offline_access.id],
  )

  include_claims_in_id_token = true
  grant_types                = ["authorization_code", "refresh_token"]

  allowed_redirect_uris = [
    {
      matching_mode = "strict"
      url           = "https://${local.grafana_host}/login/generic_oauth"
    },
  ]
}

resource "authentik_application" "grafana" {
  name              = "Grafana"
  slug              = "grafana"
  protocol_provider = authentik_provider_oauth2.grafana.id
  meta_launch_url   = "https://${local.grafana_host}"
}

resource "authentik_policy_binding" "grafana_admins" {
  target = authentik_application.grafana.uuid
  group  = authentik_group.infra_admins.id
  order  = 0
}

resource "vault_kv_secret_v2" "grafana" {
  mount = vault_mount.authentik.path
  name  = "observability/grafana"

  data_json = jsonencode({
    client_id     = authentik_provider_oauth2.grafana.client_id
    client_secret = random_password.grafana_client_secret.result
    issuer        = "${var.authentik_url}/application/o/${authentik_application.grafana.slug}/"
  })
}

resource "vault_policy" "grafana" {
  name = "authentik-observability-grafana"

  policy = <<-EOT
    path "${vault_mount.authentik.path}/data/${vault_kv_secret_v2.grafana.name}" {
      capabilities = ["read"]
    }

    path "${vault_mount.authentik.path}/metadata/${vault_kv_secret_v2.grafana.name}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "observability" {
  backend   = "kubernetes"
  role_name = "authentik-observability"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["observability"]

  token_policies = [vault_policy.grafana.name]
  token_ttl      = 3600
}
