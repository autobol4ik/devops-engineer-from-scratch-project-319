resource "yandex_iam_workload_identity_oidc_federation" "github" {
  folder_id   = var.folder_id
  name        = "${local.project}-github-wlif"
  description = "GitHub Actions OIDC for the immutable project repository identity"
  disabled    = false
  audiences   = [local.github_oidc_audience]
  issuer      = local.github_oidc_issuer
  jwks_url    = local.github_oidc_jwks_url
  labels      = local.labels
}

resource "yandex_iam_workload_identity_federated_credential" "github" {
  service_account_id  = yandex_iam_service_account.github_deploy.id
  federation_id       = yandex_iam_workload_identity_oidc_federation.github.id
  external_subject_id = local.github_oidc_subject
}

resource "yandex_iam_workload_identity_oidc_federation" "cluster" {
  folder_id   = var.folder_id
  name        = "${local.project}-cluster-wlif"
  description = "Managed Kubernetes service-account federation"
  disabled    = false
  audiences   = [yandex_kubernetes_cluster.main.workload_identity_federation[0].issuer]
  issuer      = yandex_kubernetes_cluster.main.workload_identity_federation[0].issuer
  jwks_url    = yandex_kubernetes_cluster.main.workload_identity_federation[0].jwks_uri
  labels      = local.labels
}

resource "yandex_iam_workload_identity_federated_credential" "gwin" {
  service_account_id  = yandex_iam_service_account.gwin.id
  federation_id       = yandex_iam_workload_identity_oidc_federation.cluster.id
  external_subject_id = local.gwin_external_subject
}

resource "yandex_iam_workload_identity_federated_credential" "logging" {
  service_account_id  = yandex_iam_service_account.logging.id
  federation_id       = yandex_iam_workload_identity_oidc_federation.cluster.id
  external_subject_id = local.logging_external_subject
}
