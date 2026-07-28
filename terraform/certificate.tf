resource "yandex_cm_certificate" "application" {
  folder_id   = var.folder_id
  name        = "${local.project}-bulletin-board"
  description = "Managed TLS certificate for the Project 5 application"
  domains     = [local.application_domain]
  labels      = local.labels

  managed {
    challenge_type = "HTTP"
  }
}
