data "vault_kv_secret_v2" "authentik" {
  mount = "authentik"
  name  = "netbird/netbird"
}

resource "netbird_identity_provider" "authentik" {
  name          = "Authentik"
  type          = "oidc"
  issuer        = data.vault_kv_secret_v2.authentik.data["issuer"]
  client_id     = data.vault_kv_secret_v2.authentik.data["client_id"]
  client_secret = data.vault_kv_secret_v2.authentik.data["client_secret"]
}
