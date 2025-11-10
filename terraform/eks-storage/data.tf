data "aws_caller_identity" "current" {}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "YOUR_BUCKET_NAME"
    key    = "infra/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_iam_policy_document" "assume_role_policy_pod_identity" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole", "sts:TagSession"]
  }
}