output "state_bucket_name" {
  description = "Private, versioned bucket for the main Terraform state."
  value       = yandex_storage_bucket.state.bucket
}

output "backend_service_account_id" {
  description = "Service account used only by the S3 backend."
  value       = yandex_iam_service_account.state.id
}

output "backend_access_key" {
  description = "Export as AWS_ACCESS_KEY_ID before initializing the main root. The value remains in bootstrap state."
  value       = yandex_iam_service_account_static_access_key.state.access_key
  sensitive   = true
}

output "backend_secret_key" {
  description = "Export as AWS_SECRET_ACCESS_KEY before initializing the main root. The value remains in bootstrap state."
  value       = yandex_iam_service_account_static_access_key.state.secret_key
  sensitive   = true
}
