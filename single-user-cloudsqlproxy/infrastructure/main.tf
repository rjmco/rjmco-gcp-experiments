terraform {
  required_version = "~> 0.12"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

variable "name_prefix" {
  default     = "cloudsqlproxy"
  description = "Prefix for resource names"
  type        = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

// Lists the roles required by the test GCE instance's default service account.
// Including the role to access the Cloud SQL instance
locals {
  sql_client_roles = [
    "roles/cloudsql.client",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ]
}

// Makes sure necessary APIs are activate on the project
module "project-services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "3.3.0"

  activate_apis = [
    "compute.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
  ]
  disable_dependent_services  = false
  disable_services_on_destroy = false
  project_id                  = var.project_id
}

// Creates an isolated custom VPC network for the test Cloud SQL proxy VM
resource "google_compute_network" "n0" {
  name = format("%s-%s", var.name_prefix, "n0")

  description = "VPC for the test environment"

  auto_create_subnetworks = false

  depends_on = [module.project-services]
}

// Creates a subnetwork for the test Cloud SQL proxy VM with Private Google Access (PGA) enabled.
resource "google_compute_subnetwork" "sn0" {
  ip_cidr_range = "192.168.0.0/24"
  name          = format("%s-%s", var.name_prefix, "sn0")
  network       = google_compute_network.n0.self_link

  description = "Subnetwork for the test Cloud SQL proxy VM"

  // Enables PGA to allow the Cloud SQL Proxy to coordinate access with Cloud SQL's API.
  private_ip_google_access = true
}

// Allow incoming SSH connections through an Identity-Aware Proxy tunnel.
resource "google_compute_firewall" "fw_allow_ssh_from_iap" {
  name    = format("%s-%s", var.name_prefix, "fw-allow-ssh-from-iap")
  network = google_compute_network.n0.self_link

  description = "Allows SSH through IAP"

  allow {
    ports    = ["22"]
    protocol = "tcp"
  }
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["t-allow-ssh-from-iap"]
}

resource "google_compute_global_address" "sc0_cidr_range" {
  name = format("%s-%s", var.name_prefix, "sc0-cidr-range")

  description = "A /24 CIDR range reserved for Google Private Services Access. Enough for 1 service on 1 region"

  address_type  = "INTERNAL"
  prefix_length = 24
  purpose       = "VPC_PEERING"
  network       = google_compute_network.n0.self_link
}

resource "google_service_networking_connection" "sc0" {
  network                 = google_compute_network.n0.self_link
  reserved_peering_ranges = [google_compute_global_address.sc0_cidr_range.name]
  service                 = "servicenetworking.googleapis.com"

  depends_on = [module.project-services]
}

resource "google_sql_database_instance" "sql0" {
  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.n0.self_link
      require_ssl     = true
    }
  }
  depends_on = [google_service_networking_connection.sc0]
}

resource "google_service_account" "sa0" {
  account_id = "cloudsqlproxy-client"
}

resource "google_project_iam_binding" "sa0_iam" {
  count   = length(local.sql_client_roles)
  members = [format("serviceAccount:%s", google_service_account.sa0.email)]
  role    = local.sql_client_roles[count.index]
}

data "google_compute_image" "img0" {
  family = "cloudsqlproxy-client"
}

resource "google_compute_disk" "d0" {
  name  = format("%s-%s", var.name_prefix, "d0")
  image = data.google_compute_image.img0.self_link
}

resource "google_compute_instance" "i0" {
  machine_type = "f1-micro"
  name         = format("%s-%s", var.name_prefix, "i0")
  boot_disk {
    source = google_compute_disk.d0.self_link
  }
  network_interface {
    subnetwork = google_compute_subnetwork.sn0.self_link
  }

  allow_stopping_for_update = true
  metadata = {
    cloudsql-instances = format("%s=tcp:3306", google_sql_database_instance.sql0.connection_name)
  }
  service_account {
    email  = google_service_account.sa0.email
    scopes = ["cloud-platform"]
  }
  tags = ["t-allow-ssh-from-iap"]
}

resource "google_sql_user" "i0_sql_user" {
  instance = google_sql_database_instance.sql0.name
  name     = "myapp"
  host     = format("cloudsqlproxy~%s", google_compute_instance.i0.network_interface[0].network_ip)
}

output "sql_instance_name" {
  value = google_sql_database_instance.sql0.name
}
