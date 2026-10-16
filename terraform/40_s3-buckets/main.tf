locals {
  s3_endpoint = "https://fsn1.your-objectstorage.com"
  s3_region   = "fsn1"

  buckets = {
    luuk-postgres = { namespace = "postgres", consumer = "postgres" }
    luuk-mariadb  = { namespace = "mariadb", consumer = "mariadb" }
    luuk-loki     = { namespace = "observability", consumer = "loki" }
    luuk-mimir    = { namespace = "observability", consumer = "mimir" }
  }

  namespaces = toset([for bucket in local.buckets : bucket.namespace])

  namespace_policies = {
    for namespace in local.namespaces : namespace => [
      for name, bucket in local.buckets :
      vault_policy.bucket_read[name].name if bucket.namespace == namespace
    ]
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = each.key
}

resource "vault_mount" "s3" {
  path        = "s3"
  type        = "kv-v2"
  description = "Hetzner Object Storage credentials, one path per consuming namespace."
}

resource "vault_kv_secret_v2" "credentials" {
  for_each = local.buckets

  mount = vault_mount.s3.path
  name  = "${each.value.namespace}/${each.value.consumer}"

  data_json = jsonencode({
    bucket            = aws_s3_bucket.this[each.key].bucket
    access_key_id     = var.s3_access_key_id
    secret_access_key = var.s3_secret_access_key
    region            = local.s3_region
    endpoint          = local.s3_endpoint
  })
}

resource "vault_policy" "bucket_read" {
  for_each = local.buckets

  name = "s3-${each.value.namespace}-${each.value.consumer}"

  policy = <<-EOT
    path "${vault_mount.s3.path}/data/${each.value.namespace}/${each.value.consumer}" {
      capabilities = ["read"]
    }

    path "${vault_mount.s3.path}/metadata/${each.value.namespace}/${each.value.consumer}" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_kubernetes_auth_backend_role" "namespace" {
  for_each = local.namespace_policies

  backend   = "kubernetes"
  role_name = "s3-${each.key}"

  bound_service_account_names      = ["*"]
  bound_service_account_namespaces = [each.key]

  token_policies = each.value
  token_ttl      = 3600
}
