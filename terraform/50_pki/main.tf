locals {
  device_domain = "devices.luukblankenstijn.nl"

  hosts = {
    zenbook      = {}
    thinkpad     = {}
    home-gateway = {}
    edge         = {}
  }

  phones = {
    phone = {}
  }
}

resource "vault_mount" "pki_devices" {
  path                  = "pki-devices"
  type                  = "pki"
  description           = "Root CA for device client certificates; signs only the hosts and per-phone intermediates."
  max_lease_ttl_seconds = 315360000
}

resource "vault_pki_secret_backend_root_cert" "device_ca" {
  backend              = vault_mount.pki_devices.path
  type                 = "internal"
  common_name          = "Home device CA"
  issuer_name          = "home-device-ca"
  exclude_cn_from_sans = true
  ttl                  = "87600h"
  key_type             = "ec"
  key_bits             = 256
}

resource "vault_mount" "pki_hosts" {
  path                  = "pki-hosts"
  type                  = "pki"
  description           = "Intermediate CA for host client certificates, renewed by the hosts themselves."
  max_lease_ttl_seconds = 604800
}

resource "vault_pki_secret_backend_intermediate_cert_request" "hosts" {
  backend              = vault_mount.pki_hosts.path
  type                 = "internal"
  common_name          = "Home device hosts CA"
  exclude_cn_from_sans = true
  key_type             = "ec"
  key_bits             = 256
}

resource "vault_pki_secret_backend_root_sign_intermediate" "hosts" {
  backend              = vault_mount.pki_devices.path
  issuer_ref           = vault_pki_secret_backend_root_cert.device_ca.issuer_id
  csr                  = vault_pki_secret_backend_intermediate_cert_request.hosts.csr
  common_name          = "Home device hosts CA"
  exclude_cn_from_sans = true
  ttl                  = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "hosts" {
  backend     = vault_mount.pki_hosts.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.hosts.certificate
}

resource "vault_pki_secret_backend_role" "host" {
  for_each = local.hosts

  backend    = vault_mount.pki_hosts.path
  name       = each.key
  issuer_ref = vault_pki_secret_backend_intermediate_set_signed.hosts.imported_issuers[0]

  allowed_domains    = ["${each.key}.${local.device_domain}"]
  allow_bare_domains = true
  allow_subdomains   = false
  client_flag        = true
  server_flag        = false
  no_store           = true

  ttl     = "604800"
  max_ttl = "604800"

  key_type = "ec"
  key_bits = 256
}

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Machine logins for hosts that renew their device client certificate."
}

resource "vault_policy" "host" {
  for_each = local.hosts

  name = "device-${each.key}"

  policy = <<-EOT
    path "${vault_mount.pki_hosts.path}/issue/${vault_pki_secret_backend_role.host[each.key].name}" {
      capabilities = ["update"]
    }
  EOT
}

resource "vault_approle_auth_backend_role" "host" {
  for_each = local.hosts

  backend        = vault_auth_backend.approle.path
  role_name      = "device-${each.key}"
  token_policies = [vault_policy.host[each.key].name]
  token_ttl      = 3600
  token_max_ttl  = 3600
}

resource "vault_approle_auth_backend_role_secret_id" "host" {
  for_each = local.hosts

  backend   = vault_auth_backend.approle.path
  role_name = vault_approle_auth_backend_role.host[each.key].role_name
}

resource "vault_mount" "pki_phone" {
  for_each = local.phones

  path                  = "pki-phone-${each.key}"
  type                  = "pki"
  description           = "Intermediate CA for the single client certificate of phone ${each.key}."
  max_lease_ttl_seconds = 31536000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "phone" {
  for_each = local.phones

  backend              = vault_mount.pki_phone[each.key].path
  type                 = "internal"
  common_name          = "Home device phone ${each.key} CA"
  exclude_cn_from_sans = true
  key_type             = "ec"
  key_bits             = 256
}

resource "vault_pki_secret_backend_root_sign_intermediate" "phone" {
  for_each = local.phones

  backend              = vault_mount.pki_devices.path
  issuer_ref           = vault_pki_secret_backend_root_cert.device_ca.issuer_id
  csr                  = vault_pki_secret_backend_intermediate_cert_request.phone[each.key].csr
  common_name          = "Home device phone ${each.key} CA"
  exclude_cn_from_sans = true
  ttl                  = "43800h"
}

resource "vault_pki_secret_backend_intermediate_set_signed" "phone" {
  for_each = local.phones

  backend     = vault_mount.pki_phone[each.key].path
  certificate = vault_pki_secret_backend_root_sign_intermediate.phone[each.key].certificate
}

resource "vault_pki_secret_backend_role" "phone" {
  for_each = local.phones

  backend    = vault_mount.pki_phone[each.key].path
  name       = "phone"
  issuer_ref = vault_pki_secret_backend_intermediate_set_signed.phone[each.key].imported_issuers[0]

  allowed_domains    = ["${each.key}.${local.device_domain}"]
  allow_bare_domains = true
  allow_subdomains   = false
  client_flag        = true
  server_flag        = false

  ttl     = "31536000"
  max_ttl = "31536000"

  key_type = "ec"
  key_bits = 256
}

resource "vault_pki_secret_backend_cert" "phone" {
  for_each = local.phones

  backend     = vault_mount.pki_phone[each.key].path
  name        = vault_pki_secret_backend_role.phone[each.key].name
  common_name = "${each.key}.${local.device_domain}"
  ttl         = "8760h"

  auto_renew            = true
  min_seconds_remaining = 2592000
}

resource "vault_kv_secret_v2" "device_ca" {
  mount = "secret"
  name  = "observability/device-ca"

  data_json = jsonencode({
    "ca.crt" = "${join("\n", concat(
      [vault_pki_secret_backend_root_sign_intermediate.hosts.certificate],
      [for name in sort(keys(local.phones)) : vault_pki_secret_backend_root_sign_intermediate.phone[name].certificate],
    ))}\n"
  })
}

resource "vault_policy" "device_ca_read" {
  name = "pki-traefik-device-ca"

  policy = <<-EOT
    path "secret/data/${vault_kv_secret_v2.device_ca.name}" {
      capabilities = ["read"]
    }

    path "secret/metadata/${vault_kv_secret_v2.device_ca.name}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "traefik" {
  backend   = "kubernetes"
  role_name = "pki-traefik"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["traefik"]

  token_policies = [vault_policy.device_ca_read.name]
  token_ttl      = 3600
}

resource "vault_mount" "devices" {
  path        = "devices"
  type        = "kv-v2"
  description = "Per-device credentials to copy from the UI: host AppRole logins and phone certificates."
}

resource "vault_kv_secret_v2" "host" {
  for_each = local.hosts

  mount = vault_mount.devices.path
  name  = "hosts/${each.key}"

  data_json = jsonencode({
    role_id   = vault_approle_auth_backend_role.host[each.key].role_id
    secret_id = vault_approle_auth_backend_role_secret_id.host[each.key].secret_id
  })
}

resource "vault_kv_secret_v2" "phone" {
  for_each = local.phones

  mount = vault_mount.devices.path
  name  = "phones/${each.key}"

  data_json = jsonencode({
    certificate = vault_pki_secret_backend_cert.phone[each.key].certificate
    private_key = vault_pki_secret_backend_cert.phone[each.key].private_key
    ca_chain    = vault_pki_secret_backend_cert.phone[each.key].ca_chain
  })
}

resource "vault_kv_secret_v2" "device_certificates" {
  mount = "secret"
  name  = "observability/device-certificates"

  data_json = jsonencode({
    for name in keys(local.phones) : "${name}.crt" => vault_pki_secret_backend_cert.phone[name].certificate
  })
}

resource "vault_policy" "device_certificates_read" {
  name = "pki-observability-device-certificates"

  policy = <<-EOT
    path "secret/data/${vault_kv_secret_v2.device_certificates.name}" {
      capabilities = ["read"]
    }

    path "secret/metadata/${vault_kv_secret_v2.device_certificates.name}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "observability" {
  backend   = "kubernetes"
  role_name = "pki-observability"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["observability"]

  token_policies = [vault_policy.device_certificates_read.name]
  token_ttl      = 3600
}

resource "vault_kv_secret_v2" "device_hosts_ca" {
  mount = "secret"
  name  = "home-assistant/device-hosts-ca"

  data_json = jsonencode({
    "ca.crt" = "${vault_pki_secret_backend_root_sign_intermediate.hosts.certificate}\n${vault_pki_secret_backend_root_cert.device_ca.certificate}\n"
  })
}

resource "vault_policy" "device_hosts_ca_read" {
  name = "pki-home-assistant-device-hosts-ca"

  policy = <<-EOT
    path "secret/data/${vault_kv_secret_v2.device_hosts_ca.name}" {
      capabilities = ["read"]
    }

    path "secret/metadata/${vault_kv_secret_v2.device_hosts_ca.name}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "home_assistant" {
  backend   = "kubernetes"
  role_name = "pki-home-assistant"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = ["home-assistant"]

  token_policies = [vault_policy.device_hosts_ca_read.name]
  token_ttl      = 3600
}
