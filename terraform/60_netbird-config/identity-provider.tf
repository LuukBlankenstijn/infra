data "vault_generic_secret" "authentik" {
  path = "authentik/netbird/netbird"
}

resource "netbird_identity_provider" "authentik" {
  name          = "Authentik"
  type          = "oidc"
  issuer        = data.vault_generic_secret.authentik.data["issuer"]
  client_id     = data.vault_generic_secret.authentik.data["client_id"]
  client_secret = data.vault_generic_secret.authentik.data["client_secret"]
}
