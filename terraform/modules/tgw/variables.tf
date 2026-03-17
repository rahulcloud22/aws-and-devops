variable "application_name" {
  type = string
}

variable "region" {
  description = "Region where the Transit Gateway is created"
  type        = string
  default     = null
}

variable "amazon_side_asn" {
  description = "Amazon side ASN for the Transit Gateway"
  type        = string
  default     = "64512"
}

variable "auto_accept_shared_attachments" {
  description = "Whether shared attachments are automatically accepted"
  type        = string
  default     = "disable"
}

variable "default_route_table_association" {
  description = "Enable or disable default route table association"
  type        = string
  default     = "enable"
}

variable "default_route_table_propagation" {
  description = "Enable or disable default route table propagation"
  type        = string
  default     = "enable"
}

variable "description" {
  description = "Description of the Transit Gateway"
  type        = string
  default     = ""
}

variable "dns_support" {
  description = "Enable or disable DNS support"
  type        = string
  default     = "enable"
}

variable "security_group_referencing_support" {
  description = "Enable or disable security group referencing support"
  type        = string
  default     = "disable"
}

variable "multicast_support" {
  description = "Enable or disable multicast support"
  type        = string
  default     = "disable"
}

variable "transit_gateway_cidr_blocks" {
  description = "CIDR blocks for the Transit Gateway"
  type        = list(string)
  default     = null
}

variable "vpn_ecmp_support" {
  description = "Enable or disable VPN ECMP support"
  type        = string
  default     = "enable"
}

variable "tags" {
  description = "Tags to apply to the Transit Gateway"
  type        = map(string)
  default     = {}
}

variable "tgw_attachments" {
  type = map(object({
    vpc_id                             = string
    subnet_ids                         = list(string)
    region                             = optional(string, null)
    appliance_mode_support             = optional(string, "disable")
    dns_support                        = optional(string, "enable")
    ipv6_support                       = optional(string, "disable")
    security_group_referencing_support = optional(string, "enable")
    default_route_table_association    = optional(bool, true)
    default_route_table_propagation    = optional(bool, true)
  }))
}

variable "route_tables" {
  type = map(object({
    vpc_to_attach    = optional(list(string), [])
    vpc_to_propogate = optional(list(string), [])
  }))
  default = {}
}