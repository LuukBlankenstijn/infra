variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token (read/write) for the project that holds the edge VPS. Exported from secrets/hcloud.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:DNS:Edit on luukblankenstijn.nl. Exported from secrets/cloudflare.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone id of luukblankenstijn.nl. Exported from secrets/cloudflare.yaml by .envrc; never set it by hand."
  type        = string
}
