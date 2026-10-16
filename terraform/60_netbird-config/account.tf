resource "netbird_account_settings" "this" {
  network_range              = "10.16.0.0/16"
  dns_domain                 = "peers.luuk.internal"
  jwt_groups_enabled         = true
  jwt_groups_claim_name      = "groups"
  groups_propagation_enabled = true
  user_approval_required     = false
}

resource "terraform_data" "disable_default_policy" {
  triggers_replace = [netbird_account_settings.this.id]

  provisioner "local-exec" {
    environment = {
      NB_URL   = var.netbird_url
      NB_TOKEN = var.netbird_token
    }
    command = <<-EOT
      set -euo pipefail
      id=$(curl -fsS -H "Authorization: Token $NB_TOKEN" "$NB_URL/api/policies" | jq -r '.[] | select(.name=="Default") | .id')
      if [ -n "$id" ]; then
        curl -fsS -X DELETE -H "Authorization: Token $NB_TOKEN" "$NB_URL/api/policies/$id" >/dev/null
      fi
    EOT
  }
}
