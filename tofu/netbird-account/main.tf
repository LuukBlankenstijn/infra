provider "netbird" {
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}

resource "netbird_account_settings" "this" {
  network_range = "10.16.0.0/16"
  dns_domain    = "peers.luuk.internal"
}

# Admins group. ("All" is built-in — NetBird auto-creates it for every peer.)
resource "netbird_group" "admins" {
  name = "admins"
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

# Default-deny policy with a single rule allowing admins-to-admins traffic.
# Cluster apps and other peer groups extend this from the dashboard or via
# additional resources here.
resource "netbird_policy" "admins" {
  name        = "admins"
  description = "Full mesh between admin peers"
  enabled     = true

  rule {
    name          = "admins-mesh"
    enabled       = true
    action        = "accept"
    bidirectional = true
    protocol      = "all"
    sources       = [netbird_group.admins.id]
    destinations  = [netbird_group.admins.id]
  }
}

# Reusable setup key for headless peers in the admins group. Rotate via the
# tofu lifecycle when needed (taint + apply).
resource "netbird_setup_key" "admins" {
  name        = "admins-bootstrap"
  type        = "reusable"
  usage_limit = 0 # unlimited

  auto_groups = [netbird_group.admins.id]
}

resource "netbird_dns_zone" "internal" {
  name                 = "luuk.internal"
  domain               = "luuk.internal"
  enabled              = true
  enable_search_domain = true
  distribution_groups  = [netbird_group.admins.id]
}
