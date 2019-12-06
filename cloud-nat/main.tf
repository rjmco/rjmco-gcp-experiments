# TODO: Create assertions

locals {
  dynamic_nat_ips_count = length(var.static_nat_ips) == 0 ? var.dynamic_nat_ips_count : 0
}

resource "google_compute_address" "dynamic_nat_ip" { # TODO: Make this dynamic to allow static IP to be passed along
  count        = local.dynamic_nat_ips_count
  name         = format("%s-%s%d", var.uniq_id, "ext-nat-ip", count.index)
  address_type = "EXTERNAL"
  region       = var.region
}

resource "google_compute_router" "internet_router" {
  name    = format("%s-%s", var.uniq_id, "internet-router")
  network = var.vpc
  bgp {
    asn = 64512
  }
}

resource "google_compute_router_nat" "nat0" {
  name                               = format("%s-%s", var.uniq_id, "internet-nat")
  nat_ip_allocate_option             = "MANUAL_ONLY"
  router                             = google_compute_router.internet_router.name
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  nat_ips = length(var.static_nat_ips) == 0 ? google_compute_address.dynamic_nat_ip[*].self_link : var.static_nat_ips

  subnetwork { # TODO: Use var here and dynamic if source_subnetwork_ip_ranges_to_nat != LIST_OF_SUBNETWORKS
    name                    = var.subnet
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"] # TODO: Log known limitation which may need to be improved for GKE subnets
  }
  log_config {
    enable = true  # TODO: Make variable
    filter = "ALL" # TODO: Make variable
  }
}

resource "google_compute_route" "internet_route" {
  name             = format("%s-%s", var.uniq_id, "internet-route")
  dest_range       = "0.0.0.0/0"
  network          = var.vpc
  next_hop_gateway = "default-internet-gateway"
  tags             = ["t-internet-egress-access"] # TODO: Make variable
}

