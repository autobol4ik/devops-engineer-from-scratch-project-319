terraform {
  required_version = ">= 1.8.0"

  required_providers {
    random = {
      source  = "registry.terraform.io/hashicorp/random"
      version = "~> 3.7"
    }

    yandex = {
      source  = "registry.terraform.io/yandex-cloud/yandex"
      version = "0.218.0"
    }
  }

  backend "s3" {}
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}
