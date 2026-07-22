resource "yandex_kubernetes_cluster" "main" {
  folder_id  = var.folder_id
  name       = "${local.project}-cluster"
  network_id = yandex_vpc_network.main.id

  description              = "Project 319 zonal study cluster"
  cluster_ipv4_range       = var.cluster_ipv4_range
  service_ipv4_range       = var.service_ipv4_range
  node_ipv4_cidr_mask_size = 24
  release_channel          = var.kubernetes_release_channel
  network_policy_provider  = "CALICO"

  service_account_id      = yandex_iam_service_account.kubernetes_control_plane.id
  node_service_account_id = yandex_iam_service_account.kubernetes_nodes.id
  labels                  = local.labels

  master {
    version            = var.kubernetes_version
    public_ip          = true
    security_group_ids = [yandex_vpc_security_group.master.id]

    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.private.id
    }

    scale_policy {
      auto_scale {
        min_resource_preset_id = "s-c2-m8"
      }
    }

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        day        = "sunday"
        start_time = "03:00"
        duration   = "3h"
      }
    }
  }

  workload_identity_federation {
    enabled = true
  }

  depends_on = [yandex_resourcemanager_folder_iam_member.kubernetes_control_plane]
}

resource "yandex_kubernetes_node_group" "workers" {
  cluster_id  = yandex_kubernetes_cluster.main.id
  name        = "${local.project}-workers"
  description = "Economical private worker group for project 319"
  version     = var.kubernetes_version
  labels      = local.labels

  node_labels = {
    "hexlet.io/project" = "5"
  }

  instance_template {
    name        = "${local.project}-worker-{instance.short_id}"
    platform_id = "standard-v3"

    network_interface {
      nat                = false
      subnet_ids         = [yandex_vpc_subnet.private.id]
      security_group_ids = [yandex_vpc_security_group.nodes.id]
    }

    resources {
      cores         = 2
      memory        = 4
      core_fraction = 50
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    scheduling_policy {
      preemptible = false
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = var.worker_count
    }
  }

  allocation_policy {
    location {
      zone = var.zone
    }
  }

  deploy_policy {
    max_expansion   = 1
    max_unavailable = 0
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "sunday"
      start_time = "03:00"
      duration   = "3h"
    }
  }

  workload_identity_federation {
    enabled = true
  }
}

resource "yandex_kubernetes_cluster_iam_member" "github_cluster_admin" {
  cluster_id = yandex_kubernetes_cluster.main.id
  role       = "k8s.cluster-api.cluster-admin"
  member     = "serviceAccount:${yandex_iam_service_account.github_deploy.id}"
}
