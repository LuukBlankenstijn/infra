resource "netbird_network" "home_gateway" {
  name        = "home-gateway"
  description = "Networks behind home-gateway; its routing peer is assigned in the dashboard"
}

resource "netbird_network_resource" "printer" {
  network_id  = netbird_network.home_gateway.id
  name        = "printer-lan"
  description = "Access point uap0 on home-gateway, for the 3D printer"
  address     = "10.77.0.0/24"
  groups      = [netbird_group.printer.id]
  enabled     = true
}
