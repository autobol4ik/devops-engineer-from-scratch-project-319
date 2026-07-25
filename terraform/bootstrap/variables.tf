variable "cloud_id" {
  description = "Yandex Cloud ID."
  type        = string

  validation {
    condition     = length(trimspace(var.cloud_id)) > 0
    error_message = "cloud_id must not be empty."
  }
}

variable "folder_id" {
  description = "Yandex Cloud folder ID."
  type        = string

  validation {
    condition     = length(trimspace(var.folder_id)) > 0
    error_message = "folder_id must not be empty."
  }
}

variable "zone" {
  description = "Default Yandex Cloud availability zone."
  type        = string
  default     = "ru-central1-a"
}

variable "state_bucket_prefix" {
  description = "Globally unique state bucket name prefix."
  type        = string
  default     = "hexlet-5-tfstate"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,40}$", var.state_bucket_prefix))
    error_message = "state_bucket_prefix must be a lowercase Object Storage-compatible prefix."
  }
}
