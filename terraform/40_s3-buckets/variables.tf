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

variable "s3_access_key_id" {
  description = "Hetzner Object Storage access key. Exported from secrets/s3.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "Hetzner Object Storage secret key. Exported from secrets/s3.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}
