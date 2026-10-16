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

variable "lan_address" {
  description = "LAN address of home-server, where the postgres-lan and mariadb LoadBalancer Services listen. Tofu connects here; the certificate names below are only resolvable inside the cluster."
  type        = string
  default     = "192.168.1.78"
}

variable "postgres_host" {
  description = "Name clients use for the Postgres primary. Its certificate is issued for this name, and the cluster CoreDNS rewrites it to the postgres-rw Service."
  type        = string
  default     = "postgres.luukblankenstijn.nl"
}

variable "postgres_port" {
  description = "Port of the Postgres primary."
  type        = number
  default     = 5432
}

variable "mariadb_host" {
  description = "Name clients use for the MariaDB primary. Its certificate is issued for this name, and the cluster CoreDNS rewrites it to the mariadb Service."
  type        = string
  default     = "mariadb.luukblankenstijn.nl"
}

variable "mariadb_port" {
  description = "Port of the MariaDB primary."
  type        = number
  default     = 3306
}

variable "kubeconfig_path" {
  description = "Kubeconfig used to read the provisioner credentials from the cluster. Defaults to the repository's .kube/config."
  type        = string
  default     = null
}
