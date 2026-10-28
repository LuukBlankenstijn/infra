locals {
  app_secrets     = yamldecode(var.app_secrets)
  netbird_secrets = yamldecode(var.netbird_secrets)

  ntfy_alertmanager_token = "tk_${random_string.ntfy_alertmanager_token.result}"

  secrets = {
    "netbird/server" = {
      store_encryption_key = random_bytes.netbird_store_encryption_key.base64
      session_cookie_key   = random_bytes.netbird_session_cookie_key.base64
      auth_secret          = random_password.netbird_auth_secret.result
    }
    "netbird/operator" = {
      api_key = local.netbird_secrets.api_token
    }
    "netbird/reverse-proxy" = {
      token = local.netbird_secrets.proxy_token
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
    "ntfy/ntfy" = {
      luuk_password              = random_password.ntfy_luuk.result
      luuk_password_hash         = random_password.ntfy_luuk.bcrypt_hash
      alertmanager_password_hash = random_password.ntfy_alertmanager.bcrypt_hash
      alertmanager_token         = local.ntfy_alertmanager_token
      edge_password_hash         = random_password.ntfy_edge.bcrypt_hash
      edge_token                 = var.ntfy_heartbeat_token
    }
    "observability/alertmanager" = {
      ntfy_token = local.ntfy_alertmanager_token
    }
    "home-assistant/mqtt" = {
      home_assistant_password = random_password.mqtt_home_assistant.result
      exporter_password       = random_password.mqtt_exporter.result
    }
    "pi-tunnel/frp" = {
      token      = var.frp_token
      secret_key = var.pi_tunnel_secret_key
    }
    "tunnelrs/keys" = {
      server   = local.app_secrets.tunnelrs.server_key
      operator = local.app_secrets.tunnelrs.operator_key
      ctl      = local.app_secrets.tunnelrs.ctl_key
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

resource "random_password" "ntfy_luuk" {
  length  = 32
  special = false
}

resource "random_password" "ntfy_alertmanager" {
  length  = 32
  special = false
}

resource "random_password" "ntfy_edge" {
  length  = 32
  special = false
}

resource "random_string" "ntfy_alertmanager_token" {
  length  = 29
  upper   = false
  special = false
}

resource "random_password" "authentik_bootstrap_token" {
  length  = 64
  special = false
}

resource "random_password" "mqtt_home_assistant" {
  length  = 32
  special = false
}

resource "random_password" "mqtt_exporter" {
  length  = 32
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

resource "vault_auth_backend" "oidc" {
  type        = "oidc"
  path        = "oidc"
  description = "Human login through Authentik, configured by 50_authentik-config."

  tune {
    listing_visibility = "unauth"
  }
}
