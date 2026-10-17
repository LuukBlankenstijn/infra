variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "bao_address" {
  description = "OpenBao API address."
  type        = string
  default     = "https://openbao.luukblankenstijn.nl"
}

variable "bao_role" {
  description = "OpenBao Kubernetes auth role to log in as."
  type        = string
  default     = "admin"
}

variable "bao_jwt" {
  description = "Kubernetes ServiceAccount token used to authenticate against OpenBao. Exported by bao_jwt_export in .envrc."
  type        = string
  sensitive   = true
}

variable "app_secrets" {
  description = "Decrypted secrets/apps.yaml: externally issued credentials (SMTP passwords, the existing Authentik secret key). Exported from sops by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "frp_token" {
  description = "Shared frp token, also deployed to the edge host by sops-nix. Exported from secrets/edge.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "netbird_secrets" {
  description = "Decrypted secrets/netbird.yaml: the owner PAT minted by /api/setup and the reverse-proxy token minted by `netbird-server admin token create`. Exported from sops by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "ntfy_heartbeat_token" {
  description = "ntfy token the edge host uses to read topic heartbeat, also deployed to the edge by sops-nix. Exported from secrets/edge.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}
