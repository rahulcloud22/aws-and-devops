output "cluster_role_arn" {
  description = "The ARN of the EKS cluster IAM role"
  value       = aws_iam_role.cluster_role.arn 
}

output "node_role_arn" {
  description = "The ARN of the EKS node IAM role"
  value       = aws_iam_role.node_role.arn
}

output "id" {
 description = "The name of the EKS cluster"
 value       = aws_eks_cluster.cluster.id 
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster"
  value       = aws_eks_cluster.cluster.arn
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS cluster"
  value       = aws_eks_cluster.cluster.endpoint
}

output "name" {
  description = "The namespace for the EKS cluster"
  value       = aws_eks_cluster.cluster.name
  
}