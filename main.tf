terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.228"
    }
  }
}

provider "yandex" {
  folder_id = var.folder_id
  token     = var.yc_token
}

# --- Образ Debian 11 ---
data "yandex_compute_image" "debian_11" {
  family = "debian-11"
}

# --- Существующая сеть ---
data "yandex_vpc_network" "main" {
  name = "diplom"
}

# --- Подсети ---
resource "yandex_vpc_subnet" "subnet_public" {
  name           = "subnet-public"
  zone           = var.zone_a
  network_id     = data.yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_subnet" "subnet_private_a" {
  name           = "subnet-private-a"
  zone           = var.zone_a
  network_id     = data.yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  route_table_id = yandex_vpc_route_table.private-rt.id
}

resource "yandex_vpc_subnet" "subnet_private_b" {
  name           = "subnet-private-b"
  zone           = var.zone_b
  network_id     = data.yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.30.0/24"]
  route_table_id = yandex_vpc_route_table.private-rt.id
}

# --- NAT и маршрутизация ---
resource "yandex_vpc_gateway" "nat-gw" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private-rt" {
  name       = "private-route-table"
  network_id = data.yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat-gw.id
  }
}

# --- Security Groups ---
resource "yandex_vpc_security_group" "bastion-sg" {
  name       = "bastion-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "alb-sg" {
  name       = "alb-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "web-sg" {
  name       = "web-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9100
    v4_cidr_blocks = ["192.168.10.32/32"]  # IP monitor-node
  }


  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "zabbix-sg" {
  name       = "zabbix-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 10051
    v4_cidr_blocks = ["192.168.0.0/16"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "es-sg" {
  name       = "es-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 9200
    v4_cidr_blocks = ["192.168.0.0/16"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "kibana-sg" {
  name       = "kibana-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 5601
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  platform_id = "standard-v1"
  zone        = var.zone_a

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.debian_11.id
      type     = "network-hdd"
      size     = 3
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.bastion-sg.id]
  }

  resources {
    cores  = 2
    memory = 2
  }

  metadata = {
    "ssh-keys"           = "debian:${file("${path.module}/id_ed25519.pub")}"
    "enable-oslogin"     = "false"
    "serial-port-enable" = "1"
    "user-data"          = file("${path.module}/cloud-init.yaml")
  }

}

resource "yandex_compute_instance" "web1" {
  name                      = "web1"
  platform_id               = "standard-v1"
  zone                      = var.zone_a
  hostname                  = "web1.diplom.local"
  allow_stopping_for_update = true

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.debian_11.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web-sg.id]
  }

  metadata = {
    "ssh-keys"           = "debian:${file("${path.module}/id_ed25519.pub")}"
    "enable-oslogin"     = "false"
    "serial-port-enable" = "1"
    "user-data"          = file("${path.module}/cloud-init.yaml")
  }

}

# --- Security Group for monitor-node ---
resource "yandex_vpc_security_group" "monitor-sg" {
  name       = "monitor-sg"
  network_id = data.yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 9090
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# --- monitor-node VM ---
resource "yandex_compute_instance" "monitor-node" {
  name                      = "monitor-node"
  platform_id               = "standard-v1"
  zone                      = var.zone_a
  hostname                  = "monitor.diplom.local"
  allow_stopping_for_update = true

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.debian_11.id
      type     = "network-ssd"   # рекомендую SSD вместо HDD для мониторинга
      size     = 20              # <-- добавь эту строку: 20 ГБ минимум
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet_public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.monitor-sg.id]
  }

  metadata = {
    "ssh-keys"           = "debian:${file("${path.module}/id_ed25519.pub")}"
    "enable-oslogin"     = "false"
    "serial-port-enable" = "1"
    "user-data"          = file("${path.module}/cloud-init.yaml")
  }
}
