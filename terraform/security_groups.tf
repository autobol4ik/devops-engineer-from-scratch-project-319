resource "yandex_vpc_security_group" "master" {
  folder_id   = var.folder_id
  name        = "${local.project}-k8s-master"
  description = "Public Kubernetes API and control-plane traffic"
  network_id  = yandex_vpc_network.main.id
  labels      = local.labels
}

resource "yandex_vpc_security_group" "nodes" {
  folder_id   = var.folder_id
  name        = "${local.project}-k8s-nodes"
  description = "Private Kubernetes worker nodes"
  network_id  = yandex_vpc_network.main.id
  labels      = local.labels
}

resource "yandex_vpc_security_group" "gwin" {
  folder_id   = var.folder_id
  name        = "${local.project}-gwin"
  description = "Public HTTP ALB managed by Gwin"
  network_id  = yandex_vpc_network.main.id
  labels      = local.labels
}

resource "yandex_vpc_security_group" "postgresql" {
  folder_id   = var.folder_id
  name        = "${local.project}-postgresql"
  description = "Private PostgreSQL access from Kubernetes workers"
  network_id  = yandex_vpc_network.main.id
  labels      = local.labels
}

resource "yandex_vpc_security_group_rule" "master_api_https" {
  security_group_binding = yandex_vpc_security_group.master.id
  direction              = "ingress"
  description            = "Kubernetes API HTTPS"
  protocol               = "TCP"
  port                   = 443
  v4_cidr_blocks         = var.api_allowed_cidrs
}

resource "yandex_vpc_security_group_rule" "master_api_native" {
  security_group_binding = yandex_vpc_security_group.master.id
  direction              = "ingress"
  description            = "Kubernetes API native port"
  protocol               = "TCP"
  port                   = 6443
  v4_cidr_blocks         = var.api_allowed_cidrs
}

resource "yandex_vpc_security_group_rule" "master_from_nodes" {
  security_group_binding = yandex_vpc_security_group.master.id
  direction              = "ingress"
  description            = "Worker to control-plane traffic"
  protocol               = "ANY"
  security_group_id      = yandex_vpc_security_group.nodes.id
}

resource "yandex_vpc_security_group_rule" "master_egress" {
  security_group_binding = yandex_vpc_security_group.master.id
  direction              = "egress"
  description            = "Control-plane egress"
  protocol               = "ANY"
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "nodes_self" {
  security_group_binding = yandex_vpc_security_group.nodes.id
  direction              = "ingress"
  description            = "Inter-node traffic"
  protocol               = "ANY"
  predefined_target      = "self_security_group"
}

resource "yandex_vpc_security_group_rule" "nodes_internal_ranges" {
  security_group_binding = yandex_vpc_security_group.nodes.id
  direction              = "ingress"
  description            = "Subnet, pod, and service traffic"
  protocol               = "ANY"
  v4_cidr_blocks = [
    var.network_cidr,
    var.cluster_ipv4_range,
    var.service_ipv4_range,
  ]
}

resource "yandex_vpc_security_group_rule" "nodes_from_master" {
  security_group_binding = yandex_vpc_security_group.nodes.id
  direction              = "ingress"
  description            = "Control-plane to worker traffic"
  protocol               = "ANY"
  security_group_id      = yandex_vpc_security_group.master.id
}

resource "yandex_vpc_security_group_rule" "nodes_from_gwin" {
  security_group_binding = yandex_vpc_security_group.nodes.id
  direction              = "ingress"
  description            = "Gwin ALB to application NodePort"
  protocol               = "TCP"
  port                   = 30080
  security_group_id      = yandex_vpc_security_group.gwin.id
}

resource "yandex_vpc_security_group_rule" "gwin_from_alb_health_checks" {
  security_group_binding = yandex_vpc_security_group.gwin.id
  direction              = "ingress"
  description            = "Yandex ALB resource-unit health checks"
  protocol               = "TCP"
  port                   = 30080
  predefined_target      = "loadbalancer_healthchecks"
}

resource "yandex_vpc_security_group_rule" "nodes_egress" {
  security_group_binding = yandex_vpc_security_group.nodes.id
  direction              = "egress"
  description            = "Worker egress through the shared NAT gateway"
  protocol               = "ANY"
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "gwin_http" {
  security_group_binding = yandex_vpc_security_group.gwin.id
  direction              = "ingress"
  description            = "Public HTTP"
  protocol               = "TCP"
  port                   = 80
  v4_cidr_blocks         = ["0.0.0.0/0"]
}

resource "yandex_vpc_security_group_rule" "gwin_to_nodes" {
  security_group_binding = yandex_vpc_security_group.gwin.id
  direction              = "egress"
  description            = "ALB traffic and health checks to application NodePort"
  protocol               = "TCP"
  port                   = 30080
  security_group_id      = yandex_vpc_security_group.nodes.id
}

resource "yandex_vpc_security_group_rule" "gwin_nodecheck_to_nodes" {
  security_group_binding = yandex_vpc_security_group.gwin.id
  direction              = "egress"
  description            = "Gwin nodecheck traffic to Kubernetes workers"
  protocol               = "TCP"
  port                   = 30501
  security_group_id      = yandex_vpc_security_group.nodes.id
}

resource "yandex_vpc_security_group_rule" "nodes_from_gwin_nodecheck" {
  security_group_binding = yandex_vpc_security_group.nodes.id
  direction              = "ingress"
  description            = "Gwin nodecheck traffic from the ALB"
  protocol               = "TCP"
  port                   = 30501
  security_group_id      = yandex_vpc_security_group.gwin.id
}

resource "yandex_vpc_security_group_rule" "postgresql_from_nodes" {
  security_group_binding = yandex_vpc_security_group.postgresql.id
  direction              = "ingress"
  description            = "Odyssey PostgreSQL endpoint from Kubernetes workers"
  protocol               = "TCP"
  port                   = 6432
  security_group_id      = yandex_vpc_security_group.nodes.id
}
