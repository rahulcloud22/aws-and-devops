locals {
  route_table_associations = flatten([
    for rt_name, rt in var.route_tables : [
      for vpc in rt["vpc_to_attach"] : [{
        rt  = rt_name
        vpc = vpc
  }]]])
  route_table_propagations = flatten([
    for rt_name, rt in var.route_tables : [
      for vpc in rt["vpc_to_propogate"] : [{
        rt  = rt_name
        vpc = vpc
  }]]])
}

resource "aws_ec2_transit_gateway" "tgw" {
  region                             = var.region
  amazon_side_asn                    = var.amazon_side_asn
  auto_accept_shared_attachments     = var.auto_accept_shared_attachments
  default_route_table_association    = var.default_route_table_association
  default_route_table_propagation    = var.default_route_table_propagation
  description                        = var.description
  dns_support                        = var.dns_support
  security_group_referencing_support = var.security_group_referencing_support
  multicast_support                  = var.multicast_support
  transit_gateway_cidr_blocks = var.transit_gateway_cidr_blocks
  vpn_ecmp_support = var.vpn_ecmp_support
  tags = merge({
    Name = "tgw-${var.application_name}"
  }, var.tags)
}

resource "aws_ec2_transit_gateway_vpc_attachment" "tgw_attachments" {
  for_each   = var.tgw_attachments
  vpc_id     = each.value.vpc_id
  subnet_ids = each.value.subnet_ids
  transit_gateway_id                              = aws_ec2_transit_gateway.tgw.id
  region                                          = each.value.region
  appliance_mode_support                          = each.value.appliance_mode_support
  dns_support                                     = each.value.dns_support
  ipv6_support                                    = each.value.ipv6_support
  security_group_referencing_support              = each.value.security_group_referencing_support
  transit_gateway_default_route_table_association = each.value.default_route_table_association
  transit_gateway_default_route_table_propagation = each.value.default_route_table_propagation
  tags = merge({
    Name = "tgw-attach-${data.aws_vpc.tgw_attachments[each.key].tags["Name"]}"
  }, var.tags)
}

resource "aws_ec2_transit_gateway_route_table" "tgw_rt" {
  for_each           = var.route_tables
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  tags = merge({
    Name = "tgw-rt-${each.key}-${var.application_name}"
  }, var.tags)
}

resource "aws_ec2_transit_gateway_route_table_association" "tgw_rt_associate" {
  for_each                       = { for attachments in local.route_table_associations : "${attachments.rt}-${attachments.vpc}" => attachments }
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_attachments[each.value.vpc].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.tgw_rt[each.value.rt].id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "tgw_rt_propagate" {
  for_each                       = { for attachments in local.route_table_propagations : "${attachments.rt}-${attachments.vpc}" => attachments }
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_attachments[each.value.vpc].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.tgw_rt[each.value.rt].id
}

# Route type Propagated if not Static
# resource "aws_ec2_transit_gateway_route" "tgw_rt_routes" {
#   for_each                       = var.route_tables
#   transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.tgw_rt[each.key].id
#   destination_cidr_block         = each.value.destination_cidr_block
#   transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.tgw_attachments[each.value.vpc_to_attach[0]].id
#   type                           = each.value.route_type
# }