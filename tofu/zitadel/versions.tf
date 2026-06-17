terraform {
  required_version = ">= 1.10"

  required_providers {
    # Official Zitadel provider. Pin exact — bump deliberately after reading the
    # changelog (the resource schema for OIDC apps / machine users moves).
    zitadel  = { source = "zitadel/zitadel", version = "2.12.8" }
    external = { source = "hashicorp/external", version = "~> 2.3" }
    null     = { source = "hashicorp/null", version = "~> 3.2" }
  }
}
