terraform {
  required_version = ">= 1.10"

  required_providers {
    hcloud     = { source = "hetznercloud/hcloud", version = "~> 1.50" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.0" }
    null       = { source = "hashicorp/null", version = "~> 3.2" }
    external   = { source = "hashicorp/external", version = "~> 2.3" }
  }
}
