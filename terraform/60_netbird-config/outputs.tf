output "servers_setup_key" {
  description = "Reusable setup key that enrols headless hosts into the servers group."
  value       = netbird_setup_key.servers.key
  sensitive   = true
}
