variable "project_id" {}
variable "region" { default = "europe-west2" }
variable "unique_id" {}

locals {
  cluster_nodes_subnetwork_cidr    = "192.168.0.0/22"
  cluster_pods_subnetwork_cidr     = "192.168.4.0/22"
  cluster_services_subnetwork_cidr = "192.168.8.0/22"
  cluster_master_subnetwork_cidr   = "192.168.12.0/28"
  cluster_pods_subnetwork_name     = "cluster-pods"
  cluster_services_subnetwork_name = "cluster-services"
  n0_vpn_router_asn                = 64514
  n0_vpn_router_i0_cidr_address    = "169.254.0.1/30"
  n0_vpn_router_i1_cidr_address    = "169.254.1.1/30"
  n1_vpn_router_asn                = 64515
  n1_vpn_router_i0_cidr_address    = "169.254.0.2/30"
  n1_vpn_router_i1_cidr_address    = "169.254.1.2/30"
  remote_subnetwork_cidr           = "192.168.64.0/24"
}

provider "google" {
  project = var.project_id
  region  = var.region
  version = "3.48"
}

data "google_project" "p0" {
  project_id = var.project_id
}

resource "google_compute_network" "n0" {
  name                    = format("%s-%s", "n0", var.unique_id)
  auto_create_subnetworks = false
}

resource "google_compute_network" "n1" {
  name                    = format("%s-%s", "n1", var.unique_id)
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "s0" {
  ip_cidr_range = local.cluster_nodes_subnetwork_cidr
  name          = format("%s-%s", "cluster-subnetwork", var.unique_id)
  network       = google_compute_network.n0.self_link

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = "0.5"
    metadata             = "INCLUDE_ALL_METADATA"
  }

  private_ip_google_access = true

  secondary_ip_range {
    ip_cidr_range = local.cluster_pods_subnetwork_cidr
    range_name    = local.cluster_pods_subnetwork_name
  }

  secondary_ip_range {
    ip_cidr_range = local.cluster_services_subnetwork_cidr
    range_name    = local.cluster_services_subnetwork_name
  }
}

resource "google_compute_subnetwork" "s1" {
  ip_cidr_range = local.remote_subnetwork_cidr
  name          = format("%s-%s", "remote-subnetwork", var.unique_id)
  network       = google_compute_network.n1.self_link

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = "0.5"
    metadata             = "INCLUDE_ALL_METADATA"
  }

  private_ip_google_access = true
}

resource "google_compute_firewall" "n0_ingress_allow_all" {
  name    = format("%s-%s", "n0-ingress-allow-all", var.unique_id)
  network = google_compute_network.n0.self_link

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
}

resource "google_compute_firewall" "n1_ingress_allow_all" {
  name    = format("%s-%s", "n1-ingress-allow-all", var.unique_id)
  network = google_compute_network.n1.self_link

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }
}

resource "google_container_cluster" "c0" {
  name = format("%s-%s", "cluster", var.unique_id)

  ip_allocation_policy {
    cluster_secondary_range_name  = local.cluster_pods_subnetwork_name
    services_secondary_range_name = local.cluster_services_subnetwork_name
  }

  location = var.region

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = local.cluster_nodes_subnetwork_cidr
    }
    cidr_blocks {
      cidr_block = local.remote_subnetwork_cidr
    }
  }

  network = google_compute_network.n0.self_link

  node_pool {
    initial_node_count = 0
    name               = "default-pool"
  }

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = local.cluster_master_subnetwork_cidr
  }

  subnetwork = google_compute_subnetwork.s0.self_link
}

resource "google_container_node_pool" "np0" {
  cluster = google_container_cluster.c0.name
  name    = "node-pool-0"

  initial_node_count = 1
  location           = var.region
}

// Our local test VM
resource "google_compute_instance" "i0" {
  machine_type = "n1-standard-1"
  name         = format("%s-%s", "i0", var.unique_id)

  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "debian-cloud/debian-9"
      type  = "pd-ssd"
    }
  }

  metadata = {
    unique-id = var.unique_id
  }

  metadata_startup_script = <<EOF
apt-get -y install kubectl
EOF

  network_interface {
    access_config {}
    subnetwork = google_compute_subnetwork.s0.self_link
  }

  service_account {
    scopes = ["cloud-platform"]
    email  = format("%s-compute@developer.gserviceaccount.com", data.google_project.p0.number)
  }

  zone = format("%s-%s", var.region, "b")
}

// Our remote test VM
resource "google_compute_instance" "i1" {
  machine_type = "n1-standard-1"
  name         = format("%s-%s", "i1", var.unique_id)

  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true
    initialize_params {
      image = "debian-cloud/debian-9"
      type  = "pd-ssd"
    }
  }

  metadata = {
    unique-id = var.unique_id
  }

  metadata_startup_script = <<EOF
apt-get -y install kubectl
EOF

  network_interface {
    access_config {}
    subnetwork = google_compute_subnetwork.s1.self_link
  }

  service_account {
    scopes = ["cloud-platform"]
    email  = format("%s-compute@developer.gserviceaccount.com", data.google_project.p0.number)
  }

  zone = format("%s-%s", var.region, "b")
}

resource "google_compute_ha_vpn_gateway" "n0_vpn" {
  name    = format("%s-%s", "n0-vpn-gw", var.unique_id)
  network = google_compute_network.n0.self_link
  project = var.project_id
  region  = var.region
}

resource "google_compute_ha_vpn_gateway" "n1_vpn" {
  name    = format("%s-%s", "n1-vpn-gw", var.unique_id)
  network = google_compute_network.n1.self_link
  project = var.project_id
  region  = var.region
}

resource "google_compute_router" "n0_vpn_router" {
  name    = format("%s-%s", "n0-vpn-router", var.unique_id)
  network = google_compute_network.n0.self_link
  project = var.project_id
  region  = var.region
  bgp {
    asn               = local.n0_vpn_router_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
    advertised_ip_ranges {
      description = "GKE master CIDR IP range"
      range       = local.cluster_master_subnetwork_cidr
    }
  }
}

resource "google_compute_router" "n1_vpn_router" {
  name    = format("%s-%s", "n1-vpn-router", var.unique_id)
  network = google_compute_network.n1.self_link
  project = var.project_id
  region  = var.region
  bgp {
    asn = local.n1_vpn_router_asn
  }
}

resource "random_password" "vpn_shared_secret" {
  length = 16
}

resource "google_compute_vpn_tunnel" "n0_vpn_tunnel0" {
  name                  = format("%s-%s", "n0-vpn-tunnel0", var.unique_id)
  vpn_gateway           = google_compute_ha_vpn_gateway.n0_vpn.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.n1_vpn.id
  router                = google_compute_router.n0_vpn_router.id
  shared_secret         = random_password.vpn_shared_secret.result
  vpn_gateway_interface = 0
}

resource "google_compute_vpn_tunnel" "n0_vpn_tunnel1" {
  name                  = format("%s-%s", "n0-vpn-tunnel1", var.unique_id)
  vpn_gateway           = google_compute_ha_vpn_gateway.n0_vpn.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.n1_vpn.id
  router                = google_compute_router.n0_vpn_router.id
  shared_secret         = random_password.vpn_shared_secret.result
  vpn_gateway_interface = 1
}

resource "google_compute_vpn_tunnel" "n1_vpn_tunnel0" {
  name                  = format("%s-%s", "n1-vpn-tunnel0", var.unique_id)
  vpn_gateway           = google_compute_ha_vpn_gateway.n1_vpn.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.n0_vpn.id
  router                = google_compute_router.n1_vpn_router.id
  shared_secret         = random_password.vpn_shared_secret.result
  vpn_gateway_interface = 0
}

resource "google_compute_vpn_tunnel" "n1_vpn_tunnel1" {
  name                  = format("%s-%s", "n1-vpn-tunnel1", var.unique_id)
  vpn_gateway           = google_compute_ha_vpn_gateway.n1_vpn.id
  peer_gcp_gateway      = google_compute_ha_vpn_gateway.n0_vpn.id
  router                = google_compute_router.n1_vpn_router.id
  shared_secret         = random_password.vpn_shared_secret.result
  vpn_gateway_interface = 1
}

resource "google_compute_router_interface" "n0_vpn_router_i0" {
  name       = format("%s-%s", "n0-vpn-router-i0", var.unique_id)
  router     = google_compute_router.n0_vpn_router.name
  ip_range   = local.n0_vpn_router_i0_cidr_address
  project    = var.project_id
  region     = var.region
  vpn_tunnel = google_compute_vpn_tunnel.n0_vpn_tunnel0.name
}

resource "google_compute_router_interface" "n0_vpn_router_i1" {
  name       = format("%s-%s", "n0-vpn-router-i1", var.unique_id)
  router     = google_compute_router.n0_vpn_router.name
  ip_range   = local.n0_vpn_router_i1_cidr_address
  project    = var.project_id
  region     = var.region
  vpn_tunnel = google_compute_vpn_tunnel.n0_vpn_tunnel1.name
}

resource "google_compute_router_interface" "n1_vpn_router_i0" {
  name       = format("%s-%s", "n1-vpn-router-i0", var.unique_id)
  router     = google_compute_router.n1_vpn_router.name
  ip_range   = local.n1_vpn_router_i0_cidr_address
  project    = var.project_id
  region     = var.region
  vpn_tunnel = google_compute_vpn_tunnel.n1_vpn_tunnel0.name
}

resource "google_compute_router_interface" "n1_vpn_router_i1" {
  name       = format("%s-%s", "n1-vpn-router-i1", var.unique_id)
  router     = google_compute_router.n1_vpn_router.name
  ip_range   = local.n1_vpn_router_i1_cidr_address
  project    = var.project_id
  region     = var.region
  vpn_tunnel = google_compute_vpn_tunnel.n1_vpn_tunnel1.name
}

resource "google_compute_router_peer" "n0_vpn_router_i0_peer" {
  interface       = google_compute_router_interface.n0_vpn_router_i0.name
  name            = format("%s-%s", "n0-vpn-router-i0-peer", var.unique_id)
  peer_asn        = local.n1_vpn_router_asn
  peer_ip_address = substr(local.n1_vpn_router_i0_cidr_address, 0, length(local.n1_vpn_router_i0_cidr_address) - 3)
  router          = google_compute_router.n0_vpn_router.name
  project         = var.project_id
  region          = var.region
}

resource "google_compute_router_peer" "n0_vpn_router_i1_peer" {
  interface       = google_compute_router_interface.n0_vpn_router_i1.name
  name            = format("%s-%s", "n0-vpn-router-i1-peer", var.unique_id)
  peer_asn        = local.n1_vpn_router_asn
  peer_ip_address = substr(local.n1_vpn_router_i1_cidr_address, 0, length(local.n1_vpn_router_i1_cidr_address) - 3)
  router          = google_compute_router.n0_vpn_router.name
  project         = var.project_id
  region          = var.region
}

resource "google_compute_router_peer" "n1_vpn_router_i0_peer" {
  interface       = google_compute_router_interface.n1_vpn_router_i0.name
  name            = format("%s-%s", "n1-vpn-router-i0-peer", var.unique_id)
  peer_asn        = local.n0_vpn_router_asn
  peer_ip_address = substr(local.n0_vpn_router_i0_cidr_address, 0, length(local.n0_vpn_router_i0_cidr_address) - 3)
  router          = google_compute_router.n1_vpn_router.name
  project         = var.project_id
  region          = var.region
}

resource "google_compute_router_peer" "n1_vpn_router_i1_peer" {
  interface       = google_compute_router_interface.n1_vpn_router_i1.name
  name            = format("%s-%s", "n1-vpn-router-i1-peer", var.unique_id)
  peer_asn        = local.n0_vpn_router_asn
  peer_ip_address = substr(local.n0_vpn_router_i1_cidr_address, 0, length(local.n0_vpn_router_i1_cidr_address) - 3)
  router          = google_compute_router.n1_vpn_router.name
  project         = var.project_id
  region          = var.region
}