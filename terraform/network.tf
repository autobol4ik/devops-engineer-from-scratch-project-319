resource "yandex_vpc_network" "main" {
  folder_id   = var.folder_id
  name        = "${local.project}-network"
  description = "Project 319 isolated study network"
  labels      = local.labels
}

resource "yandex_vpc_gateway" "nat" {
  folder_id   = var.folder_id
  name        = "${local.project}-nat"
  description = "Shared egress gateway for private Kubernetes workers"
  labels      = local.labels

  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private" {
  folder_id   = var.folder_id
  name        = "${local.project}-private-routes"
  description = "Default private-subnet route through the shared NAT gateway"
  network_id  = yandex_vpc_network.main.id
  labels      = local.labels

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat.id
  }
}

resource "yandex_vpc_subnet" "private" {
  folder_id      = var.folder_id
  name           = "${local.project}-private-a"
  description    = "Private project subnet in ru-central1-a"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.network_cidr]
  route_table_id = yandex_vpc_route_table.private.id
  labels         = local.labels
}
