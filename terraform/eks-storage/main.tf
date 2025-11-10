
module "eks" {
  source             = "../modules/eks"
  application_name   = var.application_name
  tags               = var.tags
  cluster_subnet_ids = data.terraform_remote_state.infra.outputs.vpc.public_subnet_ids
  node_groups = {
    dev = {
      desired_size  = 2
      min_size      = 1
      max_size      = 2
      subnet_ids    = data.terraform_remote_state.infra.outputs.vpc.public_subnet_ids
      instance_type = ["t3.medium"]
    }
  }
}

resource "aws_eks_addon" "pod_identity" {
  cluster_name = module.eks.name
  addon_name   = "eks-pod-identity-agent"
}