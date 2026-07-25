output "network" {
  description = "VPC resources used by the project."
  value = {
    network_id     = yandex_vpc_network.main.id
    private_subnet = yandex_vpc_subnet.private.id
    nat_gateway    = yandex_vpc_gateway.nat.id
  }
}

output "kubernetes_cluster_id" {
  description = "Managed Kubernetes cluster ID."
  value       = yandex_kubernetes_cluster.main.id
}

output "kubernetes_external_endpoint" {
  description = "Public Kubernetes API endpoint."
  value       = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}

output "kubernetes_ca_certificate" {
  description = "Public CA certificate used to verify the Kubernetes API."
  value       = yandex_kubernetes_cluster.main.master[0].cluster_ca_certificate
}

output "kubeconfig_command" {
  description = "Creates a temporary kubeconfig through the authenticated YC CLI; it does not contain a token in state."
  value       = "yc managed-kubernetes cluster get-credentials --id ${yandex_kubernetes_cluster.main.id} --external --force"
}

output "kubernetes_node_group" {
  description = "Fixed worker node group and requested staged size."
  value = {
    id           = yandex_kubernetes_node_group.workers.id
    worker_count = var.worker_count
  }
}

output "database_connection" {
  description = "PostgreSQL connection data. sensitive redacts CLI output but every value still exists in remote state."
  value = {
    host     = yandex_mdb_postgresql_cluster.database.host[0].fqdn
    port     = 6432
    database = yandex_mdb_postgresql_database.application.name
    username = yandex_mdb_postgresql_user.application.name
    password = random_password.database.result
    jdbc_url = "jdbc:postgresql://${yandex_mdb_postgresql_cluster.database.host[0].fqdn}:6432/${yandex_mdb_postgresql_database.application.name}?sslmode=disable"
  }
  sensitive = true
}

output "application_bucket_name" {
  description = "Private application image bucket name."
  value       = yandex_storage_bucket.application.bucket
}

output "application_s3_connection" {
  description = "Application S3 credentials. sensitive redacts CLI output but the credentials still exist in remote state."
  value = {
    bucket      = yandex_storage_bucket.application.bucket
    endpoint    = "https://storage.yandexcloud.net"
    region      = "ru-central1"
    active_slot = var.application_s3_keys.active
    key_ids     = { for slot, key in yandex_iam_service_account_static_access_key.application : slot => key.id }
    access_key  = yandex_iam_service_account_static_access_key.application[var.application_s3_keys.active].access_key
    secret_key  = yandex_iam_service_account_static_access_key.application[var.application_s3_keys.active].secret_key
  }
  sensitive = true
}

output "lockbox_secret_id" {
  description = "Single Lockbox secret read by External Secrets Operator."
  value       = yandex_lockbox_secret.project.id
}

output "lockbox_secret_version_id" {
  description = "Complete active Lockbox version containing all application fields and the Monitoring API key."
  value       = yandex_lockbox_secret_version_hashed.application.id
}

output "eso_authorized_key_json" {
  description = "Full authorized-key JSON for permanent namespace-local yc-auth Secrets. Write it directly to a protected file; never print or commit it."
  value = jsonencode({
    id                 = yandex_iam_service_account_key.external_secrets.id
    service_account_id = yandex_iam_service_account.external_secrets.id
    created_at         = yandex_iam_service_account_key.external_secrets.created_at
    key_algorithm      = "RSA_2048"
    public_key         = yandex_iam_service_account_key.external_secrets.public_key
    private_key        = yandex_iam_service_account_key.external_secrets.private_key
  })
  sensitive = true
}

output "application_log_group_id" {
  description = "Cloud Logging group with a 168-hour retention period."
  value       = yandex_logging_group.application.id
}

output "monitoring_workspace_id" {
  description = "Externally created Managed Service for Prometheus workspace. An empty value means the manual precondition is still pending."
  value       = var.monitoring_workspace_id
}

output "security_group_ids" {
  description = "Security groups consumed by the cluster, PostgreSQL, and Gwin manifests."
  value = {
    kubernetes_master = yandex_vpc_security_group.master.id
    kubernetes_nodes  = yandex_vpc_security_group.nodes.id
    gwin              = yandex_vpc_security_group.gwin.id
    postgresql        = yandex_vpc_security_group.postgresql.id
  }
}

output "service_account_ids" {
  description = "Service accounts used by application and platform components."
  value = {
    kubernetes_control_plane = yandex_iam_service_account.kubernetes_control_plane.id
    kubernetes_nodes         = yandex_iam_service_account.kubernetes_nodes.id
    application              = yandex_iam_service_account.application.id
    gwin                     = yandex_iam_service_account.gwin.id
    external_secrets         = yandex_iam_service_account.external_secrets.id
    monitoring               = yandex_iam_service_account.monitoring.id
    logging                  = yandex_iam_service_account.logging.id
    github_deploy            = yandex_iam_service_account.github_deploy.id
  }
}

output "github_workload_identity" {
  description = "GitHub Actions federation contract for the main branch."
  value = {
    federation_id = yandex_iam_workload_identity_oidc_federation.github.id
    audience      = local.github_oidc_audience
    subject       = local.github_oidc_subject
  }
}

output "cluster_workload_identity" {
  description = "Managed Kubernetes workload federation used by Gwin and Fluent Bit."
  value = {
    federation_id         = yandex_iam_workload_identity_oidc_federation.cluster.id
    issuer                = yandex_kubernetes_cluster.main.workload_identity_federation[0].issuer
    jwks_uri              = yandex_kubernetes_cluster.main.workload_identity_federation[0].jwks_uri
    gwin_subject          = local.gwin_external_subject
    logging_subject       = local.logging_external_subject
    gwin_credential_id    = yandex_iam_workload_identity_federated_credential.gwin.id
    logging_credential_id = yandex_iam_workload_identity_federated_credential.logging.id
  }
}
