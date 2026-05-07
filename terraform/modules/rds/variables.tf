variable "application_name" {
  type        = string
  description = "Application name used for resource naming"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage in GB for the RDS instance"
  default     = 10
}

variable "allow_major_version_upgrade" {
  type        = bool
  description = "Allow major version upgrades"
  default     = false
}

variable "apply_immediately" {
  type        = bool
  description = "Apply changes immediately (without waiting for the next maintenance window)"
  default     = false
}

variable "auto_minor_version_upgrade" {
  type        = bool
  description = "Enable automatic minor version upgrades"
  default     = true
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for the database instance"
  default     = null
}

variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain backups"
  default     = 0
}

variable "db_name" {
  type        = string
  description = "Name of the database to be created"
}

variable "engine" {
  type        = string
  description = "Database engine type"
}

variable "engine_version" {
  type        = string
  description = "Database engine version"
}

variable "instance_class" {
  type        = string
  description = "Instance class for the RDS database"
  default     = "db.t3.micro"
}

variable "iam_database_authentication_enabled" {
  type        = bool
  description = "Enable IAM database authentication"
  default     = false
}

variable "username" {
  type        = string
  description = "Master username for the database"
  sensitive   = true
}

variable "db_parameter_group_name" {
  type        = string
  description = "Parameter group name for the database engine"
  default     = null
}

variable "delete_automated_backups" {
  type        = bool
  description = "Delete automated backups on deletion"
  default     = true
}

variable "deletion_protection" {
  type        = bool
  description = "Enable deletion protection"
  default     = false
}

variable "kms_key_id" {
  type        = string
  description = "KMS key ID for RDS encryption"
  default     = null
}

variable "manage_master_user_password" {
  type        = bool
  description = "Manage master user password with AWS Secrets Manager"
  default     = null
}

variable "maintenance_window" {
  type        = string
  description = "Preferred maintenance window"
  default     = null
}

variable "max_allocated_storage" {
  type        = number
  description = "Maximum storage in GB for auto-scaling storage"
  default     = 0
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment"
  default     = false
}

variable "password" {
  type        = string
  description = "Master password for the database"
  sensitive   = true
  default     = null
}

variable "password_version" {
  type        = number
  description = "Version for password rotation"
  default     = 1
}

variable "port" {
  type        = number
  description = "Port for database connections"
}

variable "publicly_accessible" {
  type        = bool
  description = "Make RDS instance publicly accessible"
  default     = false
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for the RDS subnet group"
}

variable "skip_final_snapshot" {
  type        = bool
  description = "Skip final snapshot when destroying the instance"
  default     = true
}

variable "security_group_ids" {
  type        = list(string)
  description = "List of VPC security group IDs to associate with the RDS instance"
  default     = []
}

variable "storage_encrypted" {
  type        = bool
  description = "Enable encryption at rest"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Tags to apply to resources"
  default     = {}
}