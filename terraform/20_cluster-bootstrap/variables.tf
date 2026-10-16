variable "state_passphrase" {
  description = "Passphrase the state encryption key is derived from (PBKDF2, minimum 16 characters). Exported from secrets/tofu.yaml by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}

variable "kubeconfig_path" {
  description = "Path to the home cluster kubeconfig. Defaults to the repo-local .kube/config."
  type        = string
  default     = null
}

variable "sealed_secrets_key" {
  description = "Decrypted secrets/sealed-secrets.yaml holding tls_crt and tls_key: the pinned sealing keypair. Exported from sops by .envrc; never set it by hand."
  type        = string
  sensitive   = true
}
