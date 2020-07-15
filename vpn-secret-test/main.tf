provider "google" {
  region = "europe-west2"
  zone   = "europe-west2-b"
}

variable "pre_shared_key" {
  description = "VPN tunnel's pre-shared key"
}

variable "project_id" {
  description = "Project's ID"
}

resource "google_compute_vpn_tunnel" "tunnel1" {
  name          = "tunnel1"
  peer_ip       = "15.0.0.120"
  project       = var.project_id
  shared_secret = var.pre_shared_key

  target_vpn_gateway = google_compute_vpn_gateway.target_gateway.id

  depends_on = [
    google_compute_forwarding_rule.fr_esp,
    google_compute_forwarding_rule.fr_udp500,
    google_compute_forwarding_rule.fr_udp4500,
  ]
}

resource "google_compute_vpn_gateway" "target_gateway" {
  name    = "vpn1"
  network = google_compute_network.network1.id
  project = var.project_id
}

resource "google_compute_network" "network1" {
  name    = "network1"
  project = var.project_id
}

resource "google_compute_address" "vpn_static_ip" {
  name    = "vpn-static-ip"
  project = var.project_id
}

resource "google_compute_forwarding_rule" "fr_esp" {
  name        = "fr-esp"
  ip_protocol = "ESP"
  ip_address  = google_compute_address.vpn_static_ip.address
  project     = var.project_id
  target      = google_compute_vpn_gateway.target_gateway.id
}

resource "google_compute_forwarding_rule" "fr_udp500" {
  name        = "fr-udp500"
  ip_protocol = "UDP"
  port_range  = "500"
  ip_address  = google_compute_address.vpn_static_ip.address
  project     = var.project_id
  target      = google_compute_vpn_gateway.target_gateway.id
}

resource "google_compute_forwarding_rule" "fr_udp4500" {
  name        = "fr-udp4500"
  ip_protocol = "UDP"
  port_range  = "4500"
  ip_address  = google_compute_address.vpn_static_ip.address
  project     = var.project_id
  target      = google_compute_vpn_gateway.target_gateway.id
}

resource "google_compute_route" "route1" {
  name       = "route1"
  network    = google_compute_network.network1.name
  dest_range = "15.0.0.0/24"
  priority   = 1000
  project    = var.project_id

  next_hop_vpn_tunnel = google_compute_vpn_tunnel.tunnel1.id
}
