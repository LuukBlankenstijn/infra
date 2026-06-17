provider "netbird" {
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}

resource "netbird_account_settings" "this" {
  network_range = "10.16.0.0/16"
  dns_domain    = "peers.luuk.internal"
}

# Admins group — only the operator's user (luuk) and the peers they enrol.
# ("All" is built-in — NetBird auto-creates it for every peer.)
resource "netbird_group" "admins" {
  name = "admins"
}

# Servers group — headless peers enrolled with the setup key land here, kept
# separate from admin devices.
resource "netbird_group" "servers" {
  name = "servers"
}

resource "netbird_group" "kubernetes_api" {
  name = "kubernetes-api"
}

# Pull the operator user (luuk) from the live account so we can manage their
# auto_groups declaratively. The user must have logged in to the dashboard at
# least once for this lookup to succeed.
data "netbird_user" "luuk" {
  email = "me@luukblankenstijn.nl"
}

# Add luuk to the admins group via their auto_groups. Peers they enrol then
# inherit the group automatically, so the admins-mesh policy applies.
resource "netbird_user" "luuk" {
  email           = data.netbird_user.luuk.email
  name            = data.netbird_user.luuk.name
  role            = "owner" # NetBird account owner — first OIDC user gets this
  is_service_user = false
  auto_groups     = [netbird_group.admins.id]
}

# NetBird auto-creates a permissive "Default" All->All policy at account
# creation; it isn't a tofu resource, so we remove it via the API. Keyed on the
# account id so it re-runs on a fresh account (nuke + reapply).
resource "terraform_data" "disable_default_policy" {
  triggers_replace = [netbird_account_settings.this.id]

  provisioner "local-exec" {
    environment = {
      NB_URL   = var.netbird_management_url
      NB_TOKEN = var.netbird_api_token
    }
    command = <<-EOT
      set -euo pipefail
      id=$(curl -fsS -H "Authorization: Token $NB_TOKEN" "$NB_URL/api/policies" \
        | jq -r '.[] | select(.name=="Default") | .id')
      if [ -n "$id" ] && [ "$id" != "null" ]; then
        curl -fsS -X DELETE -H "Authorization: Token $NB_TOKEN" "$NB_URL/api/policies/$id" >/dev/null
        echo "removed NetBird default All->All policy ($id)"
      else
        echo "no default policy present"
      fi
    EOT
  }
}

# Admins can reach servers. bidirectional = false → admins initiate and replies
# flow on the established (stateful) connection, but servers cannot start
# connections to admins or to each other.
resource "netbird_policy" "admins_to_servers" {
  name        = "admins-to-servers"
  description = "Admins reach servers; servers cannot initiate back"
  enabled     = true

  rule {
    name          = "admins-to-servers"
    enabled       = true
    action        = "accept"
    bidirectional = false
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.servers.id]
  }
}

resource "netbird_policy" "admins_to_kubernetes_api" {
  name        = "admins-to-kubernetes-api"
  description = "Admins reach kubernetes-api"
  enabled     = true

  rule {
    name          = "admins-to-kubernetes-api"
    enabled       = true
    action        = "accept"
    bidirectional = false
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.kubernetes_api.id]
  }
}

resource "netbird_policy" "admins_to_admins" {
  name        = "admins-to-admins"
  description = "Admins reach Admins"
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

# Reusable setup key for headless server peers → servers group (NOT admins).
# Rotate via the tofu lifecycle when needed (taint + apply).
resource "netbird_setup_key" "servers" {
  name        = "servers-bootstrap"
  type        = "reusable"
  usage_limit = 0 # unlimited

  auto_groups = [netbird_group.servers.id]
}

resource "netbird_dns_zone" "internal" {
  name                 = "luuk.internal"
  domain               = "luuk.internal"
  enabled              = true
  enable_search_domain = true
  distribution_groups  = [netbird_group.admins.id]
}
