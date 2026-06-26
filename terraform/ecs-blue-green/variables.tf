variable "application_name" {
  default = "rahul"
}

variable "container_port" {
  default = 5678
}

variable "tags" {
  type    = map(string)
  default = {}
}