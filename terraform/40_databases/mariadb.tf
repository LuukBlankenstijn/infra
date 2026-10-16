locals {
  mariadb_databases = {
    grimmory = { namespace = "grimmory" }
  }

  mariadb_namespace_policies = {
    for namespace in toset([for database in local.mariadb_databases : database.namespace]) : namespace => [
      for name, database in local.mariadb_databases :
      vault_policy.mariadb[name].name if database.namespace == namespace
    ]
  }

  mariadb_privileges = [
    "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "REFERENCES", "INDEX", "ALTER",
    "CREATE TEMPORARY TABLES", "LOCK TABLES", "EXECUTE", "CREATE VIEW", "SHOW VIEW",
    "CREATE ROUTINE", "ALTER ROUTINE", "EVENT", "TRIGGER", "DELETE HISTORY", "SHOW CREATE ROUTINE",
  ]
}

resource "random_password" "mariadb" {
  for_each = local.mariadb_databases

  length  = 32
  special = false
}

resource "mysql_user" "app" {
  for_each = local.mariadb_databases

  user               = each.key
  host               = "%"
  plaintext_password = random_password.mariadb[each.key].result
  tls_option         = "SSL"
}

resource "mysql_database" "app" {
  for_each = local.mariadb_databases

  name = each.key
}

resource "mysql_grant" "app" {
  for_each = local.mariadb_databases

  user       = mysql_user.app[each.key].user
  host       = mysql_user.app[each.key].host
  database   = mysql_database.app[each.key].name
  privileges = local.mariadb_privileges
}

resource "vault_mount" "mariadb" {
  path        = "mariadb"
  type        = "kv-v2"
  description = "MariaDB user credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "mariadb" {
  for_each = local.mariadb_databases

  mount = vault_mount.mariadb.path
  name  = "${each.value.namespace}/${each.key}"

  data_json = jsonencode({
    username = mysql_user.app[each.key].user
    password = random_password.mariadb[each.key].result
    dbname   = mysql_database.app[each.key].name
    host     = var.mariadb_host
    port     = tostring(var.mariadb_port)
  })
}

resource "vault_policy" "mariadb" {
  for_each = local.mariadb_databases

  name = "mariadb-${each.value.namespace}-${each.key}"

  policy = <<-EOT
    path "${vault_mount.mariadb.path}/data/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }

    path "${vault_mount.mariadb.path}/metadata/${each.value.namespace}/${each.key}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "mariadb" {
  for_each = local.mariadb_namespace_policies

  backend   = "kubernetes"
  role_name = "mariadb-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
