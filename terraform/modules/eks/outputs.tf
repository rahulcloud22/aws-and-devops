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

output "cluster_name" {
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
output "oidc_url" {
  description = "The OIDC issuer URL for the EKS cluster"
  value = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# is created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication.
output "cluster_security_group_id" {
  description = "The security group ID for the EKS cluster"
  value = aws_eks_cluster.cluster.vpc_config[0].cluster_security_group_id
}