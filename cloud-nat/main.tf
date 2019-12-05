terraform {
  required_version = "~> 0.12"
  required_providers {
    google = "<= 2.20.0"
  }
}

variable "project" {
  type = string
}

variable "region" {
  default = "us-central1"
  type    = string
}

variable "zone" {
  default = "us-central1-a"
  type    = string
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
  version = "~> 2.5"
}

resource "google_compute_network" "n0" {
  name                            = "n0"
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "sn0" {
  ip_cidr_range = "192.168.0.0/24"
  name          = "sn0"
  network       = google_compute_network.n0.self_link
  log_config {}
  private_ip_google_access = true
}

resource "google_compute_address" "a0" {
  name         = "a0"
  address_type = "EXTERNAL"
  region       = var.region
}


resource "google_compute_router" "r0" {
  name    = "r0"
  network = google_compute_network.n0.self_link
  bgp {
    asn = 64512
  }
}

resource "google_compute_router_nat" "nat0" {
  name                               = "nat0"
  nat_ip_allocate_option             = "MANUAL_ONLY"
  router                             = google_compute_router.r0.name
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  nat_ips = [google_compute_address.a0.address]
}

