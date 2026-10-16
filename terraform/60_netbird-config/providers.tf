terraform {
  required_version = ">= 1.11"

  required_providers {
    netbird = {
      source  = "netbirdio/netbird"
      version = "~> 0.0.10"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

provider "netbird" {
  management_url = var.netbird_url
  token          = var.netbird_token
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
