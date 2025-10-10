locals {
  application_name = var.application_name != "eks" ? "${var.application_name}-eks" : var.application_name
}

resource "aws_iam_role" "cluster_role" {
  name               = "${local.application_name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "node_role" {
  name               = "${local.application_name}-node-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_node.json
}

// below policies are required for nodes
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_role.name
}

resource "aws_cloudwatch_log_group" "cluster_log_group" {
  count             = length(var.log_types) == 0 ? 0 : 1
  name              = "/aws/eks/${var.application_name}-cluster/cluster"
  retention_in_days = 1
  tags              = var.tags
}

resource "aws_eks_cluster" "cluster" {
  name                      = "${var.application_name}-cluster"
  role_arn                  = aws_iam_role.cluster_role.arn
  enabled_cluster_log_types = var.log_types // these are control plane logs
  vpc_config {
    subnet_ids             = var.cluster_subnet_ids
    endpoint_public_access = var.endpoint_public_access
  }
  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }
  upgrade_policy {
    support_type = "EXTENDED"
  }
  tags = var.tags
}

resource "aws_eks_node_group" "this" {
  for_each        = var.node_groups
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node_role.arn
  cluster_name    = aws_eks_cluster.cluster.id
  subnet_ids      = each.value.subnet_ids
  instance_types  = each.value.instance_types
  labels          = each.value.labels

  scaling_config {
    desired_size = each.value.desired_size
    min_size     = each.value.min_size
    max_size     = each.value.max_size
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  dynamic "remote_access" {
    for_each = each.value.ssh_key_name != null ? [each.value.ssh_key_name] : []
    content {
      ec2_ssh_key = remote_access.value
    }
  }
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy
  ]
}