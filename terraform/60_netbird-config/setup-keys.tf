resource "netbird_setup_key" "servers" {
  name        = "servers-bootstrap"
  type        = "reusable"
  usage_limit = 0
  auto_groups = [netbird_group.servers.id]
}
