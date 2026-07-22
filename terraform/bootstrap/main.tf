locals {
  project = "hexlet-5"

  labels = {
    project     = local.project
    environment = "study"
    managed_by  = "terraform"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "yandex_iam_service_account" "state" {
  folder_id   = var.folder_id
  name        = "${local.project}-tfstate"
  description = "Terraform backend for project 319"
}

resource "yandex_iam_service_account_static_access_key" "state" {
  service_account_id = yandex_iam_service_account.state.id
  description        = "S3 backend access for project 319"
}

# The authenticated bootstrap operator creates and configures the bucket. The
# backend service account receives no folder-wide role.
resource "yandex_storage_bucket" "state" {
  folder_id = var.folder_id
  bucket    = "${var.state_bucket_prefix}-${random_id.bucket_suffix.hex}"

  default_storage_class = "STANDARD"
  force_destroy         = false
  tags                  = local.labels

  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "yandex_storage_bucket_iam_binding" "state" {
  bucket = yandex_storage_bucket.state.bucket
  role   = "storage.editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.state.id}",
  ]
}
