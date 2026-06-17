variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "domain" {
  type    = string
  default = "luukblankenstijn.nl"
}

variable "zitadel_subdomain" {
  type    = string
  default = "id"
}

variable "netbird_subdomain" {
  type    = string
  default = "netbird"
}

variable "server_type" {
  type    = string
  default = "cpx22"
}

variable "server_location" {
  type    = string
  default = "nbg1"
}

variable "server_image" {
  type    = string
  default = "debian-13"
}

variable "ssh_pubkey" {
  type = string
}

variable "host_age_key" {
  type      = string
  sensitive = true
}

variable "flake_path" {
  type    = string
  default = "../.."
}
