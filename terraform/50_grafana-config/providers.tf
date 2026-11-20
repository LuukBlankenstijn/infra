terraform {
  required_version = ">= 1.11"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.55"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

locals {
  kubeconfig_path = coalesce(var.kubeconfig_path, "${path.module}/../../.kube/config")
}

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

data "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana"
    namespace = "observability"
  }
}

provider "grafana" {
  url  = var.grafana_url
  auth = "${data.kubernetes_secret_v1.grafana_admin.data["admin-user"]}:${data.kubernetes_secret_v1.grafana_admin.data["admin-password"]}"
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
