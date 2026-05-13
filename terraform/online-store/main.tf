module "vpc" {
  source           = "../modules/vpc"
  application_name = var.application_name
  vpc_cidr         = "10.0"
  tags             = var.tags
  eks_vpc          = true
}

resource "aws_security_group" "rds" {
  name   = "rds-sg"
  vpc_id = module.vpc.vpc_id
  tags   = var.tags
}

resource "aws_security_group_rule" "allow_me" {
  type              = "ingress"
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  security_group_id = aws_security_group.rds.id
  cidr_blocks       = ["0.0.0.0/0"]
}

module "rds" {
  source              = "../modules/rds"
  application_name    = var.application_name
  db_name             = "auth_db"
  engine              = "postgres"
  engine_version      = "17.6"
  port                = 5432
  username            = "auth_admin"
  password            = "AuthAdmin$123"
  subnet_ids          = module.vpc.public_subnet_ids
  security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible = true
  tags                = var.tags
}

module "eks" {
  source             = "../modules/eks"
  application_name   = "${var.application_name}-dev"
  tags               = var.tags
  cluster_subnet_ids = module.vpc.private_subnet_ids
  # cluster_security_group_ids = [aws_security_group.eks_cluster.id]
  # node_security_group_ids  = [aws_security_group.eks_nodes.id]
  node_groups = {
    dev = {
      desired_size   = 1
      min_size       = 1
      max_size       = 2
      subnet_ids     = module.vpc.public_subnet_ids
      instance_types = ["t3.medium"]
      ssh_key_name   = "${var.application_name}-ssh-keypair"
    }
  }
}

resource "aws_ecr_repository" "repository" { #ECR Repository (${var.application_name}-eks-apps) not empty, consider using force_delete
  name                 = "${var.application_name}-eks-apps"
  image_tag_mutability = "MUTABLE"  # "IMMUTABLE_WITH_EXCLUSION" once an image is pushed with a specific tag, it cannot be overwritten.
  force_delete         = true # Not in console
  image_tag_mutability_exclusion_filter {
    filter      = "latest*"
    filter_type = "WILDCARD"
  }
}