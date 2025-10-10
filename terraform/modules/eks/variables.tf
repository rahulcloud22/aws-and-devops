variable "application_name" {
  type    = string
  default = "eks"
}

variable "cluster_subnet_ids" {
  description = "List of subnet IDs to associate with the EKS cluster"
  type        = list(string)
}

variable "node_groups" {
  description = "Map of EKS node groups"
  type = map(object({
    desired_size   = number
    min_size       = number
    max_size       = number
    subnet_ids     = list(string)
    instance_types = optional(list(string), ["t3.medium"])
    ssh_key_name   = optional(string, null)
    labels         = optional(map(string))
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server endpoint is publicly accessible."
  type        = bool
  default     = true
}

variable "authentication_mode" {
  description = "Authentication mode for the EKS cluster access config."
  type        = string
  default     = "API_AND_CONFIG_MAP"
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Whether to grant the cluster creator admin permissions on the cluster."
  type        = bool
  default     = true
}

variable "log_types" {
  type    = list(string)
  default = []
}


variable "tags" {
  type    = map(string)
  default = {}
}

