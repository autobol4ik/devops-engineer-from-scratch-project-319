variable "cloud_id" {
  description = "Yandex Cloud ID. It can also be supplied through YC_CLOUD_ID."
  type        = string

  validation {
    condition     = length(trimspace(var.cloud_id)) > 0
    error_message = "cloud_id must not be empty."
  }
}

variable "folder_id" {
  description = "Yandex Cloud folder ID. It can also be supplied through YC_FOLDER_ID."
  type        = string

  validation {
    condition     = length(trimspace(var.folder_id)) > 0
    error_message = "folder_id must not be empty."
  }
}

variable "zone" {
  description = "Availability zone used by the zonal study environment."
  type        = string
  default     = "ru-central1-a"

  validation {
    condition     = var.zone == "ru-central1-a"
    error_message = "Project 5 is intentionally pinned to ru-central1-a."
  }
}

variable "network_cidr" {
  description = "IPv4 range for the private subnet."
  type        = string
  default     = "10.50.0.0/24"

  validation {
    condition     = can(cidrnetmask(var.network_cidr))
    error_message = "network_cidr must be a valid IPv4 CIDR."
  }
}

variable "cluster_ipv4_range" {
  description = "Non-overlapping pod address range managed by Managed Kubernetes."
  type        = string
  default     = "10.112.0.0/16"
}

variable "service_ipv4_range" {
  description = "Non-overlapping Kubernetes Service address range."
  type        = string
  default     = "10.96.0.0/16"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API. GitHub-hosted runners require a dynamic range unless a self-hosted runner is used."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && alltrue([for cidr in var.api_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "api_allowed_cidrs must contain valid IPv4 CIDRs."
  }
}

variable "kubernetes_version" {
  description = "Managed Kubernetes minor version. Verify availability with `yc managed-kubernetes list-versions` before apply."
  type        = string
  default     = "1.34"

  validation {
    condition     = var.kubernetes_version == "1.34"
    error_message = "The validated project profile uses Kubernetes 1.34."
  }
}

variable "kubernetes_release_channel" {
  description = "Managed Kubernetes release channel."
  type        = string
  default     = "REGULAR"

  validation {
    condition     = var.kubernetes_release_channel == "REGULAR"
    error_message = "The validated project profile uses the REGULAR channel."
  }
}

variable "worker_count" {
  description = "Fixed worker count: 1 for the initial deployment, 2 for the scaled deployment."
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 2], var.worker_count)
    error_message = "worker_count must be 1 or 2 for the staged assignment."
  }
}

variable "database_name" {
  description = "Application PostgreSQL database name."
  type        = string
  default     = "bulletin_board"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_name))
    error_message = "database_name must be a valid lowercase PostgreSQL identifier."
  }
}

variable "database_user" {
  description = "Application PostgreSQL owner name."
  type        = string
  default     = "bulletin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.database_user))
    error_message = "database_user must be a valid lowercase PostgreSQL identifier."
  }
}

variable "application_s3_keys" {
  description = "Two-slot S3 key rotation state. Add the inactive slot, switch active after it exists, and remove the old slot only after ESO and application checks pass."
  type = object({
    active = string
    slots  = set(string)
  })
  default = {
    active = "blue"
    slots  = ["blue"]
  }

  validation {
    condition = (
      contains(["blue", "green"], var.application_s3_keys.active) &&
      contains(var.application_s3_keys.slots, var.application_s3_keys.active) &&
      length(var.application_s3_keys.slots) >= 1 &&
      length(var.application_s3_keys.slots) <= 2 &&
      alltrue([for slot in var.application_s3_keys.slots : contains(["blue", "green"], slot)])
    )
    error_message = "application_s3_keys must contain one or both blue/green slots and active must name an existing slot."
  }
}

variable "monitoring_workspace_id" {
  description = "Existing Yandex Managed Service for Prometheus workspace ID. Create it with a supported console/API flow; the Yandex provider has no workspace resource."
  type        = string
  default     = ""
}
