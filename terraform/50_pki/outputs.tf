output "phone_certificates" {
  description = "Client certificate, private key and CA chain per phone, PEM encoded."
  value = {
    for name, cert in vault_pki_secret_backend_cert.phone : name => {
      certificate = cert.certificate
      private_key = cert.private_key
      ca_chain    = cert.ca_chain
    }
  }
  sensitive = true
}

output "host_approles" {
  description = "AppRole login per host, for the OpenBao Agent that renews the host's client certificate."
  value = {
    for name, role in vault_approle_auth_backend_role.host : name => {
      role_id   = role.role_id
      secret_id = vault_approle_auth_backend_role_secret_id.host[name].secret_id
    }
  }
  sensitive = true
}
