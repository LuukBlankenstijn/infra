locals {
  forward_auth_apps = {
    "longhorn-dashboard" = {
      name            = "Longhorn-dashboard"
      host            = "longhorn.luukblankenstijn.nl"
      group           = ""
      open_in_new_tab = false
      public          = false
    }
    "shelfmark" = {
      name            = "Shelfmark"
      host            = "shelfmark.luukblankenstijn.nl"
      group           = "Books"
      open_in_new_tab = true
      public          = false
    }
    "traefik-dashboard" = {
      name            = "Traefik-dashboard"
      host            = "traefik.luukblankenstijn.nl"
      group           = ""
      open_in_new_tab = false
      public          = false
    }
  }
}

data "authentik_property_mapping_provider_scope" "forward_auth" {
  managed_list = [
    "goauthentik.io/providers/proxy/scope-proxy",
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile",
    "goauthentik.io/providers/oauth2/scope-entitlements",
  ]
}

data "authentik_group" "booklore" {
  name          = "Booklore"
  include_users = false
}

resource "authentik_provider_proxy" "forward_auth" {
  for_each = local.forward_auth_apps

  name                  = "Provider for ${each.value.name}"
  mode                  = "forward_single"
  external_host         = "https://${each.value.host}"
  authorization_flow    = data.authentik_flow.implicit_consent.id
  invalidation_flow     = data.authentik_flow.invalidation.id
  property_mappings     = data.authentik_property_mapping_provider_scope.forward_auth.ids
  access_token_validity = "hours=24"
  intercept_header_auth = true
}

resource "authentik_application" "forward_auth" {
  for_each = local.forward_auth_apps

  name              = each.value.name
  slug              = each.key
  group             = each.value.group
  open_in_new_tab   = each.value.open_in_new_tab
  protocol_provider = authentik_provider_proxy.forward_auth[each.key].id
}

resource "authentik_policy_binding" "forward_auth_admins" {
  for_each = local.forward_auth_apps

  target = authentik_application.forward_auth[each.key].uuid
  group  = authentik_group.infra_admins.id
  order  = 0
}

resource "authentik_policy_binding" "forward_auth_public" {
  for_each = { for key, app in local.forward_auth_apps : key => app if app.public }

  target = authentik_application.forward_auth[each.key].uuid
  group  = authentik_group.public.id
  order  = 1
}

resource "authentik_policy_binding" "shelfmark_booklore" {
  target = authentik_application.forward_auth["shelfmark"].uuid
  group  = data.authentik_group.booklore.id
  order  = 1
}

resource "authentik_outpost" "embedded" {
  name               = "authentik Embedded Outpost"
  type               = "proxy"
  protocol_providers = [for key in sort(keys(local.forward_auth_apps)) : authentik_provider_proxy.forward_auth[key].id]
  config = jsonencode({
    authentik_host                   = var.authentik_url
    authentik_host_browser           = ""
    authentik_host_insecure          = false
    container_image                  = null
    docker_labels                    = null
    docker_map_ports                 = true
    docker_network                   = null
    kubernetes_disabled_components   = []
    kubernetes_httproute_annotations = {}
    kubernetes_httproute_parent_refs = []
    kubernetes_image_pull_secrets    = []
    kubernetes_ingress_annotations   = {}
    kubernetes_ingress_class_name    = null
    kubernetes_ingress_path_type     = null
    kubernetes_ingress_secret_name   = "authentik-outpost-tls"
    kubernetes_json_patches          = null
    kubernetes_namespace             = "authentik"
    kubernetes_replicas              = 1
    kubernetes_service_type          = "ClusterIP"
    log_level                        = "info"
    object_naming_template           = "ak-outpost-%(name)s"
    refresh_interval                 = "minutes=5"
  })
}
