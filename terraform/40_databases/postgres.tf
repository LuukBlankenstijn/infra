locals {
  postgres_databases = {
    authentik      = { namespace = "authentik" }
    netbird        = { namespace = "netbird" }
    netbird_events = { namespace = "netbird" }
    netbird_idp    = { namespace = "netbird" }
    vaultwarden    = { namespace = "vaultwarden" }
  }

  postgres_namespace_policies = {
    for namespace in toset([for database in local.postgres_databases : database.namespace]) : namespace => [
      for name, database in local.postgres_databases :
      vault_policy.postgres[name].name if database.namespace == namespace
    ]
  }
}

resource "random_password" "postgres" {
  for_each = local.postgres_databases

  length  = 32
  special = false
}

resource "postgresql_role" "app" {
  for_each = local.postgres_databases

  name     = each.key
  login    = true
  password = random_password.postgres[each.key].result
}

resource "postgresql_database" "app" {
  for_each = local.postgres_databases

  name  = each.key
  owner = postgresql_role.app[each.key].name
}

resource "vault_mount" "postgres" {
  path        = "postgres"
  type        = "kv-v2"
  description = "Postgres role credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "postgres" {
  for_each = local.postgres_databases

  mount = vault_mount.postgres.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    username = postgresql_role.app[each.key].name
    password = random_password.postgres[each.key].result
    dbname   = postgresql_database.app[each.key].name
    host     = var.postgres_host
    port     = tostring(var.postgres_port)
  })
}

resource "vault_policy" "postgres" {
  for_each = local.postgres_databases

  name = "postgres-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.postgres.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.postgres.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "postgres" {
  for_each = local.postgres_namespace_policies

  backend   = "kubernetes"
  role_name = "postgres-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
