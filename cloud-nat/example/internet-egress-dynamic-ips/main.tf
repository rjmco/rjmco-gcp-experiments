/////
// Module invokation
/////
module "internet-cloud-nat" {
  source = "../../" # TODO: turn into URL before final commit
  providers = {
    google = google
  }

  dynamic_nat_ips_count = var.dynamic_nat_ips_count
  project               = var.project
  region                = var.region
  subnet                = google_compute_subnetwork.client-subnet.self_link
  vpc                   = google_compute_network.vpc.self_link
  uniq_id               = var.uniq_id
  zone                  = var.zone
}

/////
// Auxiliar resources; required for the examples to work
/////
resource "google_compute_network" "vpc" {
  name                            = format("%s-%s", var.uniq_id, "vpc")
  auto_create_subnetworks         = false
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "client-subnet" {
  ip_cidr_range = "192.168.0.0/24"
  name          = format("%s-%s", var.uniq_id, "client-subnet")
  network       = google_compute_network.vpc.self_link
  log_config {}
  private_ip_google_access = true
}

resource "google_compute_instance" "internet_client" { # TODO: Comment this resource
  machine_type = "f1-micro"
  name         = format("%s-%s", var.uniq_id, "internet-client")
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-9"
    }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.client-subnet.self_link
  }
  tags = [
    "t-internet-egress-access", # TODO: Needs to be an output
    "t-allow-iap-ingress-ssh"
  ]
}

resource "google_compute_firewall" "allow_iap_ingress_ssh" {
  name    = format("%s-%s", var.uniq_id, "allow-iap-ingress-ssh")
  network = google_compute_network.vpc.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags = ["t-allow-iap-ingress-ssh"]
}
