variable "application_name" {
  type    = string
  default = "rahul-eks"
}

variable "tags" {
  type = map(string)
  default = {}
}