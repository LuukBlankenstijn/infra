resource "grafana_service_account" "mcp" {
  name = "mcp"
  role = "Editor"
}

resource "grafana_service_account_token" "mcp" {
  name               = "mcp-gateway"
  service_account_id = grafana_service_account.mcp.id
}

resource "vault_kv_secret_v2" "mcp" {
  mount = "secret"
  name  = "agents/grafana"

  data_json = jsonencode({
    token = grafana_service_account_token.mcp.key
  })
}

resource "vault_policy" "mcp" {
  name = "grafana-agents-grafana"

  policy = <<-EOT
    path "secret/data/${vault_kv_secret_v2.mcp.name}" {
      capabilities = ["read"]
    }

    path "secret/metadata/${vault_kv_secret_v2.mcp.name}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "agents" {
  backend   = "kubernetes"
  role_name = "grafana-agents"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["agents"]

  token_policies = [vault_policy.mcp.name]
  token_ttl      = 3600
}
