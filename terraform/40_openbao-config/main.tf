locals {
  app_secrets = yamldecode(var.app_secrets)

  secrets = {
    "netbird/server" = {
      store_encryption_key = random_bytes.netbird_store_encryption_key.base64
      session_cookie_key   = random_bytes.netbird_session_cookie_key.base64
      auth_secret          = random_password.netbird_auth_secret.result
    }
    "frpc/frpc" = {
      token = var.frp_token
    }
    "authentik/authentik" = {
      secret_key      = local.app_secrets.authentik.secret_key
      bootstrap_token = random_password.authentik_bootstrap_token.result
      smtp_password   = local.app_secrets.authentik.smtp_password
    }
    "vaultwarden/vaultwarden" = {
      smtp_password = local.app_secrets.vaultwarden.smtp_password
    }
  }

  namespace_policies = {
    for namespace in toset([for path, _ in local.secrets : split("/", path)[0]]) : namespace => [
      for path, _ in local.secrets : vault_policy.secret[path].name if split("/", path)[0] == namespace
    ]
  }
}

resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv-v2"
  description = "Application secrets that are generated here or copied from sops, one path per consuming namespace."
}

resource "random_bytes" "netbird_store_encryption_key" {
  length = 32
}

resource "random_bytes" "netbird_session_cookie_key" {
  length = 32
}

resource "random_password" "netbird_auth_secret" {
  length  = 64
  special = false
}

resource "random_password" "authentik_bootstrap_token" {
  length  = 64
  special = false
}

resource "vault_kv_secret_v2" "secret" {
  for_each = local.secrets

  mount     = vault_mount.secret.path
  name      = each.key
  data_json = jsonencode(each.value)
}

resource "vault_policy" "secret" {
  for_each = local.secrets

  name = "secret-${replace(each.key, "/", "-")}"

  policy = <<-EOT
    path "${vault_mount.secret.path}/data/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.secret.path}/metadata/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "secret" {
  for_each = local.namespace_policies

  backend   = "kubernetes"
  role_name = "secret-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
