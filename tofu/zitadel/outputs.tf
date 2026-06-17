# The provider marks all client ids/secrets sensitive. Read with
# `tofu output -raw <name>` when you need a value (e.g. to inspect delivery).
output "dashboard_client_id" {
  value     = zitadel_application_oidc.dashboard.client_id
  sensitive = true
}

output "cli_client_id" {
  value     = zitadel_application_oidc.cli.client_id
  sensitive = true
}

output "idp_client_id" {
  value     = zitadel_machine_user.idp.client_id
  sensitive = true
}

output "idp_client_secret" {
  value     = zitadel_machine_user.idp.client_secret
  sensitive = true
}
