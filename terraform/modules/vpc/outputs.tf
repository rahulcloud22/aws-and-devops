output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnet_ids" {
  value = [for subnet in range(3) : aws_subnet.public_subnets[subnet + 1].id]
}

output "private_subnet_ids" {
  value = [for subnet in range(3) : aws_subnet.private_subnets[subnet + 1].id]
}

output "public_rt_id" {
  value = aws_route_table.public_route.id
}
output "private_rt_id" {
  value = aws_route_table.public_route.id
}