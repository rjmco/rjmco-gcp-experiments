# TODO: Add descriptions to all variables

variable "project" {
  type = string
}

variable "region" {
  default = "us-central1"
  type    = string
}

variable "static_nat_ips_count" {
  default     = 1
  description = "Number of IPs to reserve to pass along to the module as static IPs."
  type        = number
}

variable "uniq_id" {
  type = string
}

variable "zone" {
  default = "us-central1-a"
  type    = string
}
