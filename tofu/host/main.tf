locals {
  kanidm_fqdn  = "${var.kanidm_subdomain}.${var.domain}"
  netbird_fqdn = "${var.netbird_subdomain}.${var.domain}"

  hostnames = toset([local.kanidm_fqdn, local.netbird_fqdn])
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "hcloud_ssh_key" "operator" {
  name       = "operator"
  public_key = var.ssh_pubkey
}

resource "hcloud_firewall" "netbird_host" {
  name = "netbird-host"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "33080"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # STUN / TURN control channel (coturn).
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "3478"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # TURN media relay range (narrowed via services.coturn.{min,max}-port).
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "49152-49251"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "netbird_host" {
  name        = "netbird-host"
  image       = var.server_image
  server_type = var.server_type
  location    = var.server_location

  ssh_keys     = [hcloud_ssh_key.operator.id]
  firewall_ids = [hcloud_firewall.netbird_host.id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  user_data = ""

  lifecycle {
    ignore_changes = [backups]
  }
}

resource "cloudflare_dns_record" "a" {
  for_each = local.hostnames
  zone_id  = var.cloudflare_zone_id
  name     = each.value
  type     = "A"
  content  = hcloud_server.netbird_host.ipv4_address
  ttl      = 300
  proxied  = false
}

resource "cloudflare_dns_record" "aaaa" {
  for_each = local.hostnames
  zone_id  = var.cloudflare_zone_id
  name     = each.value
  type     = "AAAA"
  content  = hcloud_server.netbird_host.ipv6_address
  ttl      = 300
  proxied  = false
}

module "deploy" {
  source = "github.com/numtide/nixos-anywhere//terraform/all-in-one?ref=1.13.0"

  nixos_system_attr      = "${var.flake_path}#nixosConfigurations.netbird-host.config.system.build.toplevel"
  nixos_partitioner_attr = "${var.flake_path}#nixosConfigurations.netbird-host.config.system.build.diskoScript"

  target_host = hcloud_server.netbird_host.ipv4_address
  target_user = "root"

  instance_id = tostring(hcloud_server.netbird_host.id)

  extra_files_script = "${path.module}/extra-files.sh"
  extra_environment  = { HOST_AGE_KEY = var.host_age_key }

  # Build closure locally; remote /nix is now its own ext4 partition with
  # 30 GB, plenty for the copy. Avoids remote /tmp pressure from cargo/go
  # build dirs (sops-install-secrets, kanidm, etc.).
  build_on_remote = false

  depends_on = [
    cloudflare_dns_record.a,
    cloudflare_dns_record.aaaa,
  ]
}
