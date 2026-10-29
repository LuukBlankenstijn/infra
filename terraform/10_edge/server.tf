locals {
  ports = jsondecode(file("${path.module}/../../nix/hosts/edge/ports.json"))

  firewall_rules = concat(
    [for port in concat([local.ports.ssh, local.ports.frpControl, local.ports.irohRelayHttps], local.ports.forwardedTcp) : { protocol = "tcp", port = tostring(port) }],
    [for port in [local.ports.stun, local.ports.irohRelayQad] : { protocol = "udp", port = tostring(port) }],
  )
}

resource "hcloud_server" "edge" {
  name        = "edge"
  server_type = "cx22"
  image       = "ubuntu-24.04"
  location    = "nbg1"

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [image, ssh_keys, user_data, public_net]
  }
}

resource "hcloud_firewall" "edge" {
  name = "edge"

  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  dynamic "rule" {
    for_each = local.firewall_rules
    content {
      direction  = "in"
      protocol   = rule.value.protocol
      port       = rule.value.port
      source_ips = ["0.0.0.0/0", "::/0"]
    }
  }

  apply_to {
    server = hcloud_server.edge.id
  }
}

import {
  to = hcloud_server.edge
  id = "110139620"
}

import {
  to = hcloud_firewall.edge
  id = "1829888"
}
