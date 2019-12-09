# TODO: Add descriptions to all variables

variable "dynamic_nat_ips_count" {
  default = 1
  type    = number
}

variable "project" {
  type = string
}

variable "region" {
  default = "us-central1"
  type    = string
}

variable "route_tag" {
  description = "Network tag name associated with the Internet Egress route"
  default     = "t-internet-egress-access"
  type        = string
}

variable "uniq_id" {
  type = string
}

variable "zone" {
  default = "us-central1-a"
  type    = string
}
