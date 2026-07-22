resource "yandex_logging_group" "application" {
  folder_id        = var.folder_id
  name             = "${local.project}-application"
  description      = "Application-only logs from namespace hexlet-5"
  retention_period = "168h"
  labels           = local.labels
}
