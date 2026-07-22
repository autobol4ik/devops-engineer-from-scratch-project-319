resource "yandex_iam_service_account" "kubernetes_control_plane" {
  folder_id   = var.folder_id
  name        = "${local.project}-k8s-control"
  description = "Managed Kubernetes control-plane resource account"
  labels      = local.labels
}

resource "yandex_iam_service_account" "kubernetes_nodes" {
  folder_id   = var.folder_id
  name        = "${local.project}-k8s-nodes"
  description = "Managed Kubernetes worker-node account"
  labels      = local.labels
}

resource "yandex_iam_service_account" "application" {
  folder_id   = var.folder_id
  name        = "${local.project}-application"
  description = "Bulletin board access to its private Object Storage bucket"
  labels      = local.labels
}

resource "yandex_iam_service_account" "gwin" {
  folder_id   = var.folder_id
  name        = "${local.project}-gwin"
  description = "Gwin controller authenticated through cluster workload identity"
  labels      = local.labels
}

resource "yandex_iam_service_account" "external_secrets" {
  folder_id   = var.folder_id
  name        = "${local.project}-eso"
  description = "External Secrets Operator Lockbox reader"
  labels      = local.labels
}

resource "yandex_iam_service_account" "monitoring" {
  folder_id   = var.folder_id
  name        = "${local.project}-monitoring"
  description = "Prometheus remote write to Yandex Monitoring"
  labels      = local.labels
}

resource "yandex_iam_service_account" "logging" {
  folder_id   = var.folder_id
  name        = "${local.project}-logging"
  description = "Fluent Bit writes application logs to Cloud Logging"
  labels      = local.labels
}

resource "yandex_iam_service_account" "github_deploy" {
  folder_id   = var.folder_id
  name        = "${local.project}-github-deploy"
  description = "GitHub Actions deployment through workload identity federation"
  labels      = local.labels
}

# This authorized key is the permanent root of trust for the namespace-local
# yc-auth Secrets. Its JSON payload is exposed only through a sensitive output
# and remains protected by the versioned remote Terraform state.
resource "yandex_iam_service_account_key" "external_secrets" {
  service_account_id = yandex_iam_service_account.external_secrets.id
  description        = "External Secrets Operator bootstrap authorization"
  key_algorithm      = "RSA_2048"
  format             = "PEM_FILE"
}

resource "yandex_iam_service_account_api_key" "monitoring" {
  for_each = toset(["blue"])

  service_account_id = yandex_iam_service_account.monitoring.id
  description        = "Project 319 Monitoring API key"
  scopes             = ["yc.monitoring.manage"]

  lifecycle {
    # The API also exposes a deprecated singular scope field which can cause a
    # false diff even when the configured scopes list is unchanged.
    ignore_changes = [scope]
  }
}

resource "yandex_resourcemanager_folder_iam_member" "kubernetes_control_plane" {
  for_each = toset([
    "k8s.clusters.agent",
    "vpc.publicAdmin",
  ])

  folder_id   = var.folder_id
  role        = each.value
  member      = "serviceAccount:${yandex_iam_service_account.kubernetes_control_plane.id}"
  sleep_after = 5
}

resource "yandex_resourcemanager_folder_iam_member" "gwin" {
  for_each = toset([
    "alb.editor",
    "certificate-manager.certificates.downloader",
    "certificate-manager.editor",
    "compute.viewer",
    "k8s.viewer",
    "vpc.publicAdmin",
  ])

  folder_id = var.folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.gwin.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "monitoring" {
  folder_id = var.folder_id
  role      = "monitoring.editor"
  member    = "serviceAccount:${yandex_iam_service_account.monitoring.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "logging" {
  folder_id = var.folder_id
  role      = "logging.writer"
  member    = "serviceAccount:${yandex_iam_service_account.logging.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "github_cluster_viewer" {
  folder_id = var.folder_id
  role      = "k8s.viewer"
  member    = "serviceAccount:${yandex_iam_service_account.github_deploy.id}"
}
