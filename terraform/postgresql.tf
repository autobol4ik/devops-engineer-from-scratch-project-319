resource "random_password" "database" {
  length  = 32
  special = false
}

resource "yandex_mdb_postgresql_cluster" "database" {
  folder_id           = var.folder_id
  name                = "${local.project}-postgresql"
  description         = "Single-host PostgreSQL for the project 319 study deployment"
  environment         = "PRODUCTION"
  network_id          = yandex_vpc_network.main.id
  security_group_ids  = [yandex_vpc_security_group.postgresql.id]
  deletion_protection = false
  labels              = local.labels

  config {
    version                   = "17"
    backup_retain_period_days = 7

    resources {
      resource_preset_id = "b2.medium"
      disk_type_id       = "network-hdd"
      disk_size          = 10
    }
  }

  maintenance_window {
    type = "ANYTIME"
  }

  host {
    zone             = var.zone
    subnet_id        = yandex_vpc_subnet.private.id
    assign_public_ip = false
  }
}

resource "yandex_mdb_postgresql_user" "application" {
  cluster_id               = yandex_mdb_postgresql_cluster.database.id
  name                     = var.database_user
  password                 = random_password.database.result
  conn_limit               = 50
  login                    = true
  user_password_encryption = "USER_PASSWORD_ENCRYPTION_SCRAM_SHA_256"
}

resource "yandex_mdb_postgresql_database" "application" {
  cluster_id = yandex_mdb_postgresql_cluster.database.id
  name       = var.database_name
  owner      = yandex_mdb_postgresql_user.application.name
  lc_collate = "en_US.UTF-8"
  lc_type    = "en_US.UTF-8"
}
