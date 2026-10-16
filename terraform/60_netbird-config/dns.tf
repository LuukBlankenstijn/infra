resource "netbird_dns_zone" "internal" {
  name                 = "luuk.internal"
  domain               = "luuk.internal"
  enabled              = true
  enable_search_domain = true
  distribution_groups  = [netbird_group.admins.id]
}
