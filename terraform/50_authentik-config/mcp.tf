resource "authentik_provider_oauth2" "mcp" {
  name               = "MCP gateway"
  client_id          = "mcp"
  client_type        = "public"
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
      matching_mode = "regex"
      url           = "^http://(localhost|127\\.0\\.0\\.1):[0-9]+/callback$"
    },
  ]
}

resource "authentik_application" "mcp" {
  name              = "MCP gateway"
  slug              = "mcp"
  protocol_provider = authentik_provider_oauth2.mcp.id
}

resource "authentik_policy_binding" "mcp_admins" {
  target = authentik_application.mcp.uuid
  group  = authentik_group.infra_admins.id
  order  = 0
}
