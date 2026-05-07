# RDS Module

This Terraform module provisions an AWS RDS database instance with encryption, backup, and security best practices.

## Features

- AWS RDS instance with MySQL/PostgreSQL/MariaDB support
- Encryption at rest using KMS
- Secrets Manager integration for password management
- DB subnet group for VPC isolation
- Configurable backup retention
- Deletion protection options
- Comprehensive tagging support

## Usage

```hcl
module "rds" {
  source = "./modules/rds"

  application_name       = "my-app"
  allocated_storage      = 100
  db_engine             = "mysql"
  db_engine_version     = "8.0"
  db_instance_class     = "db.t3.micro"
  db_username           = "admin"
  password              = var.db_password
  kms_key_id            = aws_kms_key.rds.id
  subnet_ids            = aws_subnet.db[*].id
  security_group_ids    = [aws_security_group.rds.id]
  
  backup_retention_period = 7
  skip_final_snapshot    = false
  deletion_protection    = true

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

## Requirements

- Terraform >= 1.0
- AWS Provider >= 5.0

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| application_name | Application name used for resource naming | `string` | n/a | yes |
| allocated_storage | Allocated storage in GB for the RDS instance | `number` | n/a | yes |
| password | Master password for the database | `string` | n/a | yes |
| kms_key_id | KMS key ID for RDS encryption | `string` | n/a | yes |
| subnet_ids | List of subnet IDs for the RDS subnet group | `list(string)` | n/a | yes |
| db_name | Name of the database to be created | `string` | `"messages"` | no |
| db_engine | Database engine type | `string` | `"mysql"` | no |
| db_engine_version | Database engine version | `string` | `"8.0"` | no |
| db_instance_class | Instance class for the RDS database | `string` | `"db.t3.micro"` | no |
| db_username | Master username for the database | `string` | `"sqladmin"` | no |
| db_parameter_group_name | Parameter group name for the database engine | `string` | `"default.mysql8.0"` | no |
| allow_major_version_upgrade | Allow major version upgrades | `bool` | `false` | no |
| password_version | Version for password rotation | `number` | `1` | no |
| skip_final_snapshot | Skip final snapshot when destroying the instance | `bool` | `true` | no |
| port | Port for database connections | `number` | `3306` | no |
| manage_master_user_password | Manage master user password with AWS Secrets Manager | `bool` | `true` | no |
| security_group_ids | List of VPC security group IDs to associate with the RDS instance | `list(string)` | `[]` | no |
| backup_retention_period | Number of days to retain backups | `number` | `7` | no |
| delete_automated_backups | Delete automated backups on deletion | `bool` | `true` | no |
| deletion_protection | Enable deletion protection | `bool` | `false` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| db_endpoint | RDS instance endpoint |
| db_address | RDS instance address |
| db_port | RDS instance port |
| db_name | Name of the database |
| db_resource_id | RDS instance resource ID |
| db_instance_id | RDS instance identifier |
| db_master_username | Master username (sensitive) |
| db_subnet_group_name | DB subnet group name |

## Security Considerations

- Passwords are sensitive and should be managed via Terraform variables or AWS Secrets Manager
- Enable deletion protection in production environments
- Use appropriate security groups to restrict database access
- Encryption at rest is enabled by default using KMS
- Regular backups are configured with configurable retention period

## Notes

- The module uses Secrets Manager to manage the master user password by default
- Password changes are tracked via the `password_version` variable
- Auto minor version upgrades are enabled; major upgrades require explicit configuration
- The instance is not publicly accessible by default
