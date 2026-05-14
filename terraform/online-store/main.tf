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
  node_groups = {
    dev = {
      desired_size   = 1
      min_size       = 1
      max_size       = 2
      subnet_ids     = module.vpc.public_subnet_ids
      instance_types = ["t3.medium"]
      ssh_key_name   = "${var.application_name}-ssh-keypair"
    }
    qa = {
      desired_size   = 1
      min_size       = 1
      max_size       = 2
      subnet_ids     = module.vpc.private_subnet_ids
      instance_types = ["t3.medium"]
      ssh_key_name   = "${var.application_name}-ssh-keypair"
    }
  }
}

resource "aws_ecr_repository" "repository" {
  name                 = "${var.application_name}-eks-apps"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_tag_mutability_exclusion_filter {
    filter      = "latest*"
    filter_type = "WILDCARD"
  }
}

resource "aws_cognito_user_pool" "pool" {
  name                     = "${var.application_name}-cognito-user-pool"
  username_attributes      = ["email"]
  auto_verified_attributes = []
  tags                     = var.tags
  lambda_config {
    pre_sign_up = aws_lambda_function.pre_signup.arn
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name                                 = "local-webapp-client"
  user_pool_id                         = aws_cognito_user_pool.pool.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows = [
    "code"
  ]
  allowed_oauth_scopes = [
    "openid",
    "email",
    "profile"
  ]
  supported_identity_providers = [
    "COGNITO"
  ]
  callback_urls = [
    "http://localhost:3000/callback",
  ]
  logout_urls = [
    "http://localhost:3000/",
  ]
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
  ]
}

data "archive_file" "pre_signup_zip" {
  type        = "zip"
  source_file = "${path.module}/scripts/cognito_lambda.js"
  output_path = "${path.module}/scripts/cognito_lambda.zip"
}

resource "aws_lambda_permission" "allow_cognito" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_signup.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.pool.arn
}

resource "aws_lambda_function" "pre_signup" {
  function_name    = "${var.application_name}-cognito-lambda"
  role             = aws_iam_role.lambda_role.arn
  handler          = "cognito_lambda.handler"
  runtime          = "nodejs18.x"
  filename         = "${path.module}/scripts/cognito_lambda.zip"
  source_code_hash = data.archive_file.pre_signup_zip.output_base64sha256
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.application_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}