# TODO: Create assertions

resource "google_compute_router" "internet_router" {
  name    = format("%s-%s", var.uniq_id, "internet-router")
  network = var.vpc
  bgp {
    asn = 64512
  }
}

resource "google_compute_router_nat" "nat0" {
  name                               = format("%s-%s", var.uniq_id, "internet-nat")
  nat_ip_allocate_option             = var.nat_ip_allocate_option
  router                             = google_compute_router.internet_router.name
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS" # TODO: Add compliance reference

  min_ports_per_vm = 57344 # TODO: add compliance reference
  nat_ips          = var.nat_ip_allocate_option == "AUTO_ONLY" ? null : var.static_nat_ips
  subnetwork { # TODO: Add compliance reference
    name                    = var.subnet
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"] # TODO: Log known limitation which may need to be improved for GKE subnets
  }
  log_config {
    enable = var.log_config.enable
    filter = var.log_config.filter
  }
}

resource "google_compute_route" "internet_route" {
  name             = format("%s-%s", var.uniq_id, "internet-route")
  dest_range       = "0.0.0.0/0"
  network          = var.vpc
  next_hop_gateway = "default-internet-gateway"
  tags             = [var.route_tag]
}
