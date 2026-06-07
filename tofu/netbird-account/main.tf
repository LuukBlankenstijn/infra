provider "netbird" {
  management_url = var.netbird_management_url
  token          = var.netbird_api_token
}

# Groups visible in the NetBird dashboard. Members are added as peers join.
resource "netbird_group" "admins" {
  name = "admins"
}

resource "netbird_group" "all" {
  name = "all"
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
