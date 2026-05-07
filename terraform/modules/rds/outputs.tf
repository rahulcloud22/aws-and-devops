output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.rds.endpoint
}

output "db_address" {
  description = "RDS instance address"
  value       = aws_db_instance.rds.address
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.rds.port
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.rds.db_name
}

output "db_resource_id" {
  description = "RDS instance resource ID"
  value       = aws_db_instance.rds.resource_id
}

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = aws_db_instance.rds.identifier
}

output "db_master_username" {
  description = "Master username"
  value       = aws_db_instance.rds.username
  sensitive   = true
}

output "db_subnet_group_name" {
  description = "DB subnet group name"
  value       = aws_db_subnet_group.db_subnet.name
}