locals {
  application_name = var.application_name != "ecs" ? "${var.application_name}-ecs" : var.application_name
}

module "vpc" {
  source           = "../modules/vpc"
  application_name = local.application_name
  vpc_cidr         = "10.0"
  tags             = var.tags
}

resource "aws_security_group" "ecr_endpoints" {
  name        = "${local.application_name}-ecr-endpoints-sg"
  description = "Allow HTTPS to ECR private endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecr_repository" "repository" {
  name                 = "flask-metrics-app"
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  force_delete         = true
  image_tag_mutability_exclusion_filter {
    filter      = "latest*"
    filter_type = "WILDCARD"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_ids = [
    aws_security_group.ecr_endpoints.id
  ]
  private_dns_enabled = true
  tags = merge(var.tags, {
    Name = "ecr-api-endpoint"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_ids = [
    aws_security_group.ecr_endpoints.id
  ]
  private_dns_enabled = true
  tags = merge({
    Name = "ecr-dkr-endpoint"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_ids = [
    aws_security_group.ecr_endpoints.id
  ]
  private_dns_enabled = true
  tags = merge({
    Name = "logs-endpoint"
  })
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.vpc.private_rt_id]
  tags = merge({
    Name = "vpc-endpoint-s3"
  })
}

resource "aws_ecr_repository_policy" "restrict_to_vpce" {
  repository = aws_ecr_repository.repository.name
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "DenyIfNotFromVpce",
        Effect    = "Deny",
        Principal = "*",
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ],
        Condition = {
          StringNotEquals = {
            "aws:sourceVpce" : [
              aws_vpc_endpoint.ecr_api.id,
              aws_vpc_endpoint.ecr_dkr.id
            ]
          }
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "rules" {
  repository = aws_ecr_repository.repository.name
  policy     = data.aws_ecr_lifecycle_policy_document.rules.json
}

resource "aws_secretsmanager_secret" "ecs_secrets" {
  name                    = "${local.application_name}-secrets"
  description             = "This is a super secret for ECS Containers"
  recovery_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${local.application_name}/logs"
  retention_in_days = 1
  tags              = var.tags
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.application_name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name       = aws_ecs_cluster.cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE_SPOT"
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.application_name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${local.application_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs-task-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role--secert-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_ecs_task_definition" "application_sidecar_definition" {
  family                   = "application-sidecar-task-definition"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048

  container_definitions = jsonencode([
    {
      name              = "application-container"
      image             = "${aws_ecr_repository.repository.repository_url}:latest"
      essential         = true
      memoryReservation = 512
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
      environment = []
      logConfiguration = {
        logDriver = "awsfirelens",
        options = {
          Name        = "newrelic",
          Retry_Limit = "2"
        },
        secretOptions = [
          {
            name      = "apiKey",
            valueFrom = "${aws_secretsmanager_secret.ecs_secrets.arn}:NEW_RELIC_LICENSE_KEY::"
          }
        ]
      }
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${local.application_name}/logs",
          awslogs-region        = "${data.aws_region.current.region}",
          awslogs-stream-prefix = "fargate"
        }
      },
    },
    {
      essential = true,
      image     = "533243300146.dkr.ecr.us-east-2.amazonaws.com/newrelic/logging-firelens-fluentbit",
      name      = "log_router",
      firelensConfiguration = {
        type = "fluentbit",
        options = {
          "enable-ecs-log-metadata" = "true"
        }
      }
    },
    {
      "environment" : [
        {
          "name" : "NRIA_OVERRIDE_HOST_ROOT",
          "value" : ""
        },
        {
          "name" : "NRIA_IS_FORWARD_ONLY",
          "value" : "true"
        },
        {
          "name" : "FARGATE",
          "value" : "true"
        },
        {
          "name" : "NRIA_PASSTHROUGH_ENVIRONMENT",
          "value" : "ECS_CONTAINER_METADATA_URI,ECS_CONTAINER_METADATA_URI_V4,FARGATE"
        },
        {
          "name" : "NRIA_CUSTOM_ATTRIBUTES",
          "value" : "{\"nrDeployMethod\":\"downloadPage\"}"
        }
      ],
      "secrets" : [
        {
          "valueFrom" : "${aws_secretsmanager_secret.ecs_secrets.arn}:NEW_RELIC_LICENSE_KEY::",
          "name" : "NRIA_LICENSE_KEY"
        }
      ],
      "cpu" : 256,
      "memoryReservation" : 512,
      "image" : "newrelic/nri-ecs:1.13.4",
      "name" : "newrelic-infra",
      "essential" : false
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn
}

resource "aws_ecs_service" "fargate_service" {
  name            = "fargate-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.application_sidecar_definition.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.ecr_endpoints.id]
  }
  lifecycle {
    ignore_changes = [desired_count]
  }
  tags = var.tags
}


# EC2 - ECS
resource "aws_iam_role" "instance_role" {
  name               = "${local.application_name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_instance_profile" "profile" {
  name = "${local.application_name}-instance-profile-ec2"
  role = aws_iam_role.instance_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonECS_FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
  role       = aws_iam_role.instance_role.name
}

resource "aws_instance" "ecs_container_instance" {
  ami           = jsondecode(data.aws_ssm_parameter.ecs_ami.value).image_id
  instance_type = "t3.medium"
  subnet_id     = module.vpc.public_subnet_ids[0]
  depends_on    = [aws_ecs_cluster.cluster]
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = 0.02
    }
  }
  iam_instance_profile = aws_iam_instance_profile.profile.name
  tags = merge(var.tags, {
    Name = "${local.application_name}"
  })
  vpc_security_group_ids = [aws_security_group.ecr_endpoints.id]
  user_data              = <<EOF
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config
EOF
}


resource "aws_ecs_task_definition" "ec2_application_definition" {
  family = "ec2-application-task-definition"
  tags   = var.tags
  container_definitions = jsonencode([
    {
      name              = "application-container"
      image             = "${aws_ecr_repository.repository.repository_url}:latest"
      essential         = true
      memoryReservation = 512
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]
      environment = [
        {
          "name"  = "AWS_SECRET_NAME"
          "value" = "${aws_secretsmanager_secret.ecs_secrets.name}"
        },
        {
          "name"  = "NEW_RELIC_APP_NAME"
          "value" = "Python ECS App"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs",
        options = {
          awslogs-group         = "/ecs/${local.application_name}/logs",
          awslogs-region        = "${data.aws_region.current.region}",
          awslogs-stream-prefix = "fargate"
        }
      },
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn      = aws_iam_role.ecs_task_role.arn
}

resource "aws_ecs_service" "ec2_service" {
  name                   = "ec2-service"
  cluster                = aws_ecs_cluster.cluster.id
  task_definition        = aws_ecs_task_definition.ec2_application_definition.arn
  desired_count          = 1
  launch_type            = "EC2"
  enable_execute_command = true
  tags                   = var.tags
}


resource "aws_ecs_task_definition" "newrelic_definition" {
  family                   = "newrelic-task-definition"
  tags                     = var.tags
  requires_compatibilities = ["EC2", "EXTERNAL"]
  network_mode             = "host"
  volume {
    name      = "host_root_fs"
    host_path = "/"
  }
  volume {
    name      = "docker_socket"
    host_path = "/var/run/docker.sock"
  }
  container_definitions = jsonencode([
    {
      "name" : "newrelic-infra",
      "image" : "newrelic/nri-ecs:1.13.4",
      "essential" : true,
      "privileged" : true,
      "readonlyRootFilesystem" : false,
      "secrets" : [
        {
          "valueFrom" : "${aws_secretsmanager_secret.ecs_secrets.arn}:NEW_RELIC_LICENSE_KEY::",
          "name" : "NRIA_LICENSE_KEY"
        }
      ],
      "portMappings" : [],
      "cpu" : 200,
      "memory" : 384,
      "environment" : [
        {
          "name" : "NRIA_OVERRIDE_HOST_ROOT",
          "value" : "/host"
        },
        {
          "name" : "NRIA_PASSTHROUGH_ENVIRONMENT",
          "value" : "ECS_CONTAINER_METADATA_URI,ECS_CONTAINER_METADATA_URI_V4"
        },
        {
          "name" : "NRIA_VERBOSE",
          "value" : "0"
        },
        {
          "name" : "NRIA_CUSTOM_ATTRIBUTES",
          "value" : "{\"nrDeployMethod\":\"downloadPage\"}"
        }
      ],
      "mountPoints" : [
        {
          "readOnly" : true,
          "containerPath" : "/host",
          "sourceVolume" : "host_root_fs"
        },
        {
          "readOnly" : false,
          "containerPath" : "/var/run/docker.sock",
          "sourceVolume" : "docker_socket"
        }
      ],
      "volumesFrom" : []
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
}

resource "aws_ecs_service" "newrelic_service" {
  name                = "newrelic-service"
  cluster             = aws_ecs_cluster.cluster.id
  task_definition     = aws_ecs_task_definition.newrelic_definition.arn
  desired_count       = 1
  launch_type         = "EC2"
  scheduling_strategy = "DAEMON"
  tags                = var.tags
}