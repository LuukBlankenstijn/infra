locals {
  sealed_secrets       = yamldecode(var.sealed_secrets_key)
  sealing_key_revision = parseint(substr(sha256(local.sealed_secrets.tls_crt), 0, 8), 16)
}

resource "kubernetes_namespace_v1" "sealed_secrets" {
  metadata {
    name = "sealed-secrets"
  }
}

resource "kubernetes_secret_v1" "sealing_key" {
  metadata {
    name      = "sealing-key-pinned"
    namespace = kubernetes_namespace_v1.sealed_secrets.metadata[0].name
    labels = {
      "sealedsecrets.bitnami.com/sealed-secrets-key" = "active"
    }
  }

  type = "kubernetes.io/tls"

  data_wo = {
    "tls.crt" = local.sealed_secrets.tls_crt
    "tls.key" = local.sealed_secrets.tls_key
  }

  data_wo_revision = local.sealing_key_revision
}
