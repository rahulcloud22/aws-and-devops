data "aws_region" "current" {}

data "aws_ecr_lifecycle_policy_document" "rules" {
  rule {
    priority    = 20 # "any" must have the highest value for priority and will be evaluated last.
    description = "Expire images older than 2 day"
    selection {
      tag_status   = "any"
      count_type   = "sinceImagePushed"
      count_unit   = "days"
      count_number = 2 # Expire images older than 2 days
    }
  }

  rule {
    priority    = 10
    description = "When there are more than 10 matching images with dev*, ECR deletes the oldest ones."
    selection {
      tag_status      = "tagged"
      tag_prefix_list = ["dev"]
      count_type      = "imageCountMoreThan"
      count_number    = 10 # Keep only the most recent 10 images with the "dev" tag
    }
  }
}

# Fargate and Container Task Role Assume Policy
data "aws_iam_policy_document" "ecs_task_assume_role_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# EC2 Instance Role Assume Policy
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended"
}