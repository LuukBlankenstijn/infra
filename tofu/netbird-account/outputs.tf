output "servers_setup_key" {
  value     = netbird_setup_key.servers.key
  sensitive = true
}
