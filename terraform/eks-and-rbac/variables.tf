variable "application_name" {
  type    = string
  default = "eks"
}

variable "tags" {
  type    = map(string)
  default = {}
}