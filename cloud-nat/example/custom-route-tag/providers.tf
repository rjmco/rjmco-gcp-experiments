provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
  version = "~> 2.5"
}

