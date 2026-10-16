locals {
  admin_destinations = {
    servers        = netbird_group.servers.id
    kubernetes-api = netbird_group.kubernetes_api.id
    ollama         = netbird_group.ollama.id
  }
}

resource "netbird_policy" "admins_to" {
  for_each = local.admin_destinations

  name        = "admins-to-${each.key}"
  description = "Admins reach ${each.key}; it cannot initiate back"
  enabled     = true

  rule {
    name          = "admins-to-${each.key}"
    enabled       = true
    action        = "accept"
    bidirectional = false
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [each.value]
  }
}

resource "netbird_policy" "admins_to_admins" {
  name        = "admins-to-admins"
  description = "Admin devices reach each other"
  enabled     = true

  rule {
    name          = "admins-to-admins"
    enabled       = true
    action        = "accept"
    bidirectional = true
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.admins.id]
  }
}
