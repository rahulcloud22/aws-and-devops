variable "application_name" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0"
}

variable "eks_vpc" {
  type    = bool
  default = false
}

variable "tags" {
}