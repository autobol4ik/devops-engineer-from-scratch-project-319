resource "yandex_lockbox_secret" "project" {
  folder_id           = var.folder_id
  name                = "${local.project}-secrets"
  description         = "Single project secret for application and platform credentials"
  deletion_protection = false
  labels              = local.labels
}

# Hashed versions keep only hashes of these payload values in the Lockbox
# version resource. The source DB password, S3 keys, and Monitoring API key
# are still present in their own Terraform resources and sensitive outputs, so
# the remote state remains sensitive and must stay in the private, versioned
# backend bucket.
resource "yandex_lockbox_secret_version_hashed" "application" {
  secret_id   = yandex_lockbox_secret.project.id
  description = "Complete application and Monitoring credentials"

  lifecycle {
    create_before_destroy = true
  }

  key_1        = "SPRING_DATASOURCE_URL"
  text_value_1 = "jdbc:postgresql://${yandex_mdb_postgresql_cluster.database.host[0].fqdn}:6432/${yandex_mdb_postgresql_database.application.name}?sslmode=disable"
  key_2        = "SPRING_DATASOURCE_USERNAME"
  text_value_2 = yandex_mdb_postgresql_user.application.name
  key_3        = "SPRING_DATASOURCE_PASSWORD"
  text_value_3 = random_password.database.result
  key_4        = "STORAGE_S3_BUCKET"
  text_value_4 = yandex_storage_bucket.application.bucket
  key_5        = "STORAGE_S3_ACCESSKEY"
  text_value_5 = yandex_iam_service_account_static_access_key.application[var.application_s3_keys.active].access_key
  key_6        = "STORAGE_S3_SECRETKEY"
  text_value_6 = yandex_iam_service_account_static_access_key.application[var.application_s3_keys.active].secret_key
  key_7        = "MONITORING_API_KEY"
  text_value_7 = yandex_iam_service_account_api_key.monitoring["blue"].secret_key
}

resource "yandex_lockbox_secret_iam_member" "external_secrets" {
  secret_id = yandex_lockbox_secret.project.id
  role      = "lockbox.payloadViewer"
  member    = "serviceAccount:${yandex_iam_service_account.external_secrets.id}"
}
