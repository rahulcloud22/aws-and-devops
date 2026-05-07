resource "aws_db_subnet_group" "db_subnet" {
  name       = "db-subnet-group-${var.application_name}"
  subnet_ids = var.subnet_ids #Subnet groups must span at least 2 AZs for failover, maintancenace etc.
  tags       = var.tags
}

resource "aws_db_instance" "rds" {
  depends_on                          = [aws_db_subnet_group.db_subnet]
  allocated_storage                   = var.allocated_storage
  allow_major_version_upgrade         = var.allow_major_version_upgrade
  apply_immediately                   = var.apply_immediately
  auto_minor_version_upgrade          = var.auto_minor_version_upgrade
  availability_zone                   = var.availability_zone # optional, AWS will choose one for bases on subnet group
  backup_retention_period             = var.backup_retention_period
  db_name                             = var.db_name
  db_subnet_group_name                = aws_db_subnet_group.db_subnet.name
  deletion_protection                 = var.deletion_protection
  delete_automated_backups            = var.delete_automated_backups
  engine                              = var.engine
  engine_version                      = var.engine_version
  final_snapshot_identifier           = !var.skip_final_snapshot ? "${var.application_name}-rds-final-snapshot" : null
  identifier                          = "${var.application_name}-rds" // this is the rds instance name
  instance_class                      = var.instance_class
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  kms_key_id                          = var.kms_key_id
  maintenance_window                  = var.maintenance_window
  max_allocated_storage               = var.max_allocated_storage
  manage_master_user_password         = var.manage_master_user_password //creates random secret manager
  master_user_secret_kms_key_id       = var.kms_key_id != null ? var.kms_key_id : null
  multi_az = var.multi_az
  parameter_group_name                = var.db_parameter_group_name
  password_wo                            = var.password                                       // password_wo does not store password in state file . password stores in state..  /', '@', '"', ' ' cannot be used.
  password_wo_version                 = var.password != null ? var.password_version : null // triggers password update when password changes
  port                                = var.port
  publicly_accessible                 = var.publicly_accessible # gives a public endpoint and IP. if false only vpc can resolve - amazon provided dnsw
  skip_final_snapshot                 = var.skip_final_snapshot
  storage_encrypted                   = var.storage_encrypted // if true, kms_key is taken else aws managed account rds kms key will be used
  username                            = var.username
  vpc_security_group_ids              = var.security_group_ids # if not provided, default vpc sg will be used
  tags                                = var.tags
}