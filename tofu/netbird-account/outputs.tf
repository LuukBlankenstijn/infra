output "admins_setup_key" {
  value     = netbird_setup_key.admins.key
  sensitive = true
}
