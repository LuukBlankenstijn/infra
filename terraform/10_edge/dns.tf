
resource "cloudflare_dns_record" "edge" {
  zone_id = var.cloudflare_zone_id
  name    = "hertzner.luukblankenstijn.nl"
  type    = "A"
  content = hcloud_server.edge.ipv4_address
  ttl     = 1
  proxied = false
}

resource "cloudflare_dns_record" "wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.luukblankenstijn.nl"
  type    = "CNAME"
  content = cloudflare_dns_record.edge.name
  ttl     = 1
  proxied = false
}

import {
  to = cloudflare_dns_record.edge
  id = "${var.cloudflare_zone_id}/d9f1eb5734297f242da18f722e98f89b"
}

import {
  to = cloudflare_dns_record.wildcard
  id = "${var.cloudflare_zone_id}/1180e030aa96af2bdb17950638902598"
}
