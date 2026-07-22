resource "random_id" "infrastructure_suffix" {
  byte_length = 4
}

resource "yandex_iam_service_account_static_access_key" "application" {
  for_each = var.application_s3_keys.slots

  service_account_id = yandex_iam_service_account.application.id
  description        = "Project 319 application S3 key (${each.key} rotation slot)"
}

resource "yandex_storage_bucket" "application" {
  folder_id = var.folder_id
  bucket    = "${local.project}-app-${random_id.infrastructure_suffix.hex}"

  default_storage_class = "STANDARD"
  force_destroy         = false
  tags                  = local.labels

  anonymous_access_flags {
    read        = false
    list        = false
    config_read = false
  }

  lifecycle_rule {
    id                                     = "abort-incomplete-uploads"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 7
  }
}

resource "yandex_storage_bucket_iam_binding" "application" {
  bucket = yandex_storage_bucket.application.bucket
  role   = "storage.editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.application.id}",
  ]
}
