terraform {
  required_version = ">= 1.11"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2026.8"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

data "kubernetes_secret_v1" "authentik_auth" {
  metadata {
    name      = "authentik-auth"
    namespace = "authentik"
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = data.kubernetes_secret_v1.authentik_auth.data["AUTHENTIK_BOOTSTRAP_TOKEN"]
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
