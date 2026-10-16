terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }
}

provider "aws" {
  region     = local.s3_region
  access_key = var.s3_access_key_id
  secret_key = var.s3_secret_access_key

  endpoints {
    s3 = local.s3_endpoint
  }

  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_requesting_account_id  = true
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
