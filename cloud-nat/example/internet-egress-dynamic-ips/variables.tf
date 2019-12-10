# TODO: Add descriptions to all variables

variable "project" {
  type = string
}

variable "region" {
  default = "us-central1"
  type    = string
}

variable "uniq_id" {
  type = string
}

variable "zone" {
  default = "us-central1-a"
  type    = string
}
