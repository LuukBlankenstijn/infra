locals {
  flux_system_path   = "${path.module}/../../flux/clusters/home/flux-system"
  flux_operator_helm = yamldecode(file("${local.flux_system_path}/helm-release.yaml")).spec
}

module "flux_operator_bootstrap" {
  source  = "controlplaneio-fluxcd/flux-operator-bootstrap/kubernetes"
  version = "0.8.0"

  revision = 1

  gitops_resources = {
    instance_yaml = file("${local.flux_system_path}/flux-instance.yaml")
    operator_chart = {
      version     = local.flux_operator_helm.chart.spec.version
      values_yaml = yamlencode(local.flux_operator_helm.values)
    }
  }

  depends_on = [kubernetes_secret_v1.sealing_key]
}
