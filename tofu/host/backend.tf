terraform {
  backend "s3" {
    bucket = "luuk"
    key    = "host/terraform.tfstate"
    region = "fsn1"

    endpoints = { s3 = "https://fsn1.your-objectstorage.com" }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true

    use_lockfile = true
  }

  encryption {
    key_provider "pbkdf2" "default" {
      passphrase = "$TF_STATE_PASSPHRASE"
    }
    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.default
    }
    state {
      method   = method.aes_gcm.default
      enforced = true
    }
    plan {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}
