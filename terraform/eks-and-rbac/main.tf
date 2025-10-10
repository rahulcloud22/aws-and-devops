module "vpc" {
  source           = "../modules/vpc"
  application_name = var.application_name
  vpc_cidr         = "10.0"
  tags             = var.tags
}

module "eks" {
  source             = "../modules/eks"
  application_name   = var.application_name
  tags               = var.tags
  cluster_subnet_ids = module.vpc.public_subnet_ids
  node_groups = {
    dev = {
      desired_size  = 1
      min_size      = 1
      max_size      = 2
      subnet_ids    = module.vpc.public_subnet_ids
      instance_type = ["t3.medium"]
    }
  }
}

resource "aws_iam_policy" "eks_developer_policy" {
  name        = "EKS-Developer-Policy"
  description = "Allow accessing EKS clusters"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster","secretsmanager:GetSecretValue"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role       = aws_iam_role.pod_role.name
  policy_arn = aws_iam_policy.eks_developer_policy.arn
}

resource "aws_iam_role" "pod_role" {
  name               = "eks-pod-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_pod.json
}

resource "aws_eks_access_entry" "user_entry" {
  cluster_name      = module.eks.id
  principal_arn     = "arn:aws:iam:::user/eks-developer"
  type              = "STANDARD"
  kubernetes_groups = ["dev-reader-group"]
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = module.eks.name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_eks_access_policy_association" "cluster_viewer" {
  cluster_name  =  module.eks.id
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/eks-developer"
  
  access_scope {
    type       = "namespace"
    namespaces = ["dev"]
  }
}

# requires Amazon EKS Pod Identity Agent add-on
# If the setup is correct AWS_* will be in env vars
resource "aws_eks_pod_identity_association" "pod_aws" {
  cluster_name    = module.eks.name
  namespace       = "dev"
  service_account = "dev-sa"
  role_arn        = aws_iam_role.pod_role.arn
}

resource "aws_secretsmanager_secret" "pod_secret" {
  name        = "pod-secret"
  description = "This is a super secret for EKS Pods"
}

resource "aws_secretsmanager_secret_version" "secret" {
  secret_id     = aws_secretsmanager_secret.pod_secret.id

  secret_string = jsonencode({
    secret = "very-super-secret"})
}