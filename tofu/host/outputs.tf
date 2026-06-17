output "server_id" { value = hcloud_server.netbird_host.id }
output "ipv4" { value = hcloud_server.netbird_host.ipv4_address }
output "ipv6" { value = hcloud_server.netbird_host.ipv6_address }
output "zitadel_url" { value = "https://${local.zitadel_fqdn}" }
output "zitadel_fqdn" { value = local.zitadel_fqdn }
output "netbird_url" { value = "https://${local.netbird_fqdn}" }
