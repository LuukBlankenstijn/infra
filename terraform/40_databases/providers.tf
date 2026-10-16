terraform {
  required_version = ">= 1.11"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    mysql = {
      source  = "petoju/mysql"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
  }
}

locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

data "kubernetes_secret_v1" "postgres_provisioner" {
  metadata {
    name      = "postgres-app"
    namespace = "postgres"
  }
}

data "kubernetes_secret_v1" "mariadb_provisioner" {
  metadata {
    name      = "mariadb-provisioner"
    namespace = "mariadb"
  }
}

provider "vault" {
  address = var.bao_address

  auth_login {
    path = "auth/kubernetes/login"
    parameters = {
      role = var.bao_role
      jwt  = var.bao_jwt
    }
  }
}

provider "postgresql" {
  host            = var.lan_address
  port            = var.postgres_port
  username        = data.kubernetes_secret_v1.postgres_provisioner.data["username"]
  password        = data.kubernetes_secret_v1.postgres_provisioner.data["password"]
  sslmode         = "require"
  superuser       = false
  connect_timeout = 15
}

provider "mysql" {
  endpoint = "${var.lan_address}:${var.mariadb_port}"
  username = "provisioner"
  password = data.kubernetes_secret_v1.mariadb_provisioner.data["password"]
  tls      = "skip-verify"
}
