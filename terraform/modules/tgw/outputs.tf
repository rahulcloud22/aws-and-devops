output "tgw_id" {
  value = aws_ec2_transit_gateway.tgw.id
}

output "tgw_arn" {
  value = aws_ec2_transit_gateway.tgw.arn
}

output "route_tables" {
  description = "Map of TGW route tables with IDs"
  value = {
    for k, rt in aws_ec2_transit_gateway_route_table.tgw_rt :
    k => {
      id = rt.id
    }
  }
}