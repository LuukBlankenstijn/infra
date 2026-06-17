variable "zitadel_domain" {
  type        = string
  default     = "id.luukblankenstijn.nl"
  description = "Public Zitadel host. DNS points it at the Tier-0 box, so it doubles as the SSH target for reading the bootstrap PAT and delivering generated values."
}

variable "netbird_domain" {
  type        = string
  default     = "netbird.luukblankenstijn.nl"
  description = "NetBird dashboard host (OIDC redirect origin)."
}

variable "org_name" {
  type        = string
  default     = "infra"
  description = "Name of the Zitadel org created by the host's FirstInstance step."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "SSH user on the Tier-0 box (key auth via ssh-agent, same as the host deploy)."
}
