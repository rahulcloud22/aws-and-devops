locals {
  application_name = var.application_name != "ecs" ? "${var.application_name}-ecs" : var.application_name
}

module "vpc" {
  source           = "../modules/vpc"
  application_name = local.application_name
  vpc_cidr         = "10.0"
  tags             = var.tags
}

resource "aws_ecs_cluster" "cluster" {
  name = "${local.application_name}-cluster"
}

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/${local.application_name}-ecs/logs"
  retention_in_days = 1
  tags              = var.tags
}

# what the ECS agent needs to start and manage your container like pulling image from ECR, getting secrets etc
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${local.application_name}-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role_policy.json
}
resource "aws_iam_role_policy_attachment" "ecs-task-execution-role-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ecs-task-execution-role--secert-policy-attachment" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

resource "aws_iam_role" "ecs_alb_role" {
  name               = "${local.application_name}-alb-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

resource "aws_iam_role" "ecs_lambda_role" {
  name               = "${local.application_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

resource "aws_iam_role_policy" "ecs_alb_role_policy" {
  name = "${var.application_name}-ecs-alb-role-policy"
  role = aws_iam_role.ecs_alb_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeListeners"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ],
        Resource = [
          aws_lb_target_group.ecs_blue_tg.arn,
          aws_lb_target_group.ecs_green_tg.arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:ModifyListener"
        ],
        Resource = [
          aws_lb_listener.prod_listener.arn,
          aws_lb_listener.test_listener.arn
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:ModifyRule"
        ],
        Resource = [
          aws_lb_listener_rule.prod_listener_rule.arn,
          aws_lb_listener_rule.test_listener_rule.arn
          # "arn:aws:elasticloadbalancing:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:listener-rule/app/${aws_lb.ecs_alb.name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_lambda_role_policy" {
  name = "${var.application_name}-ecs-lambda-role-policy"
  role = aws_iam_role.ecs_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
        ]
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "lifecycle_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/scripts/lifecycle_lambda.py"
  output_path = "${path.module}/scripts/lifecycle_lambda.zip"
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.application_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "lifecycle_handler" {
  function_name    = "${var.application_name}-lifecycle-handler"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.14"
  handler          = "lifecycle_lambda.lambda_handler"
  filename         = "scripts/lifecycle_lambda.zip"
  timeout          = 120
  source_code_hash = data.archive_file.lifecycle_lambda_zip.output_base64sha256
  depends_on       = [data.archive_file.lifecycle_lambda_zip]
}

resource "aws_security_group" "alb_sg" {
  name        = "${local.application_name}-alb-sg"
  description = "controls access to the ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "application_sg" {
  name        = "${local.application_name}-application-sg"
  description = "Allow traffic to application"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = var.container_port
    to_port     = var.container_port
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

resource "aws_lb" "ecs_alb" {
  name               = "${local.application_name}-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnet_ids
  tags               = var.tags
  security_groups    = [aws_security_group.alb_sg.id]
}

resource "aws_lb_target_group" "ecs_blue_tg" {
  name        = "ecs-blue-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
  tags        = var.tags
}

resource "aws_lb_target_group" "ecs_green_tg" {
  name        = "ecs-green-tg"
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
  tags        = var.tags
}

resource "aws_lb_listener" "prod_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.ecs_blue_tg.arn
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "prod_listener_rule" {
  listener_arn = aws_lb_listener.prod_listener.arn
  priority     = 100
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.ecs_blue_tg.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.ecs_green_tg.arn
        weight = 0
      }
    }
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_listener" "test_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.ecs_green_tg.arn
    type             = "forward"
  }
}


resource "aws_lb_listener_rule" "test_listener_rule" {
  listener_arn = aws_lb_listener.test_listener.arn
  priority     = 100
  action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.ecs_blue_tg.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.ecs_green_tg.arn
        weight = 0
      }
    }
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
  lifecycle {
    ignore_changes = [action]
  }
}


resource "aws_ecs_task_definition" "app_task" {
  family                   = "echo-task-definition"
  requires_compatibilities = ["FARGATE"] #Fargate always requires awsvpc networking.
  network_mode             = "awsvpc"    #means each ECS task gets its own network card (ENI), private IP address, and security group—just like a small EC2 instance.
  cpu                      = 1024
  memory                   = 2048
  container_definitions = jsonencode([
    {
      name      = "echo-container"
      image     = "hashicorp/http-echo:latest"
      essential = true
      portMappings = [
        {
          containerPort = var.container_port // for fargate, container and host port should match
          hostPort      = var.container_port //if not using a lb or fargate, 2 containers cannot have same port.
        }
      ],
      command = ["-text=Hello from version 3"]
    }
  ])
  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn
  skip_destroy       = true
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_service" "app_service" {
  name            = "echo-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = module.vpc.public_subnet_ids
    assign_public_ip = true     // req to be true for tasks in public subnet
    security_groups  = [aws_security_group.application_sg.id] #which security group(s) to attach to that ENI.
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_blue_tg.arn
    container_name   = "echo-container" #A single ECS task can run more than one container
    container_port   = var.container_port
    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.ecs_green_tg.arn
      role_arn                   = aws_iam_role.ecs_alb_role.arn
      production_listener_rule   = aws_lb_listener_rule.prod_listener_rule.arn
      test_listener_rule         = aws_lb_listener_rule.test_listener_rule.arn
    }
  }
  deployment_controller {
    type = "ECS"
  }
  alarms {
    enable   = true
    rollback = true
    alarm_names = [
      aws_cloudwatch_metric_alarm.ecs_alarm.alarm_name
    ]
  }
  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = 5
    lifecycle_hook {
      hook_target_arn  = aws_lambda_function.lifecycle_handler.arn
      role_arn         = aws_iam_role.ecs_lambda_role.arn
      lifecycle_stages = ["PRE_SCALE_UP", "TEST_TRAFFIC_SHIFT", "PRODUCTION_TRAFFIC_SHIFT"]
    }
  }
  lifecycle {
    ignore_changes = [desired_count]
  }
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "ecs_alarm" {
  alarm_name          = "ecs-rollback-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 60
  metric_name         = "RollbackTrigger"
  namespace           = "ECS/BlueGreen"
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Dummy alarm to trigger ECS rollback"
}

# aws cloudwatch put-metric-data \
#   --namespace "ECS/BlueGreen" \
#   --metric-data MetricName=RollbackTrigger,Value=0