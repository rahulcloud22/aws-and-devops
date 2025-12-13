variable "application_name" {
  default = "ecs-python"
}

variable "tags" {
  type    = map(string)
  default = {}
}