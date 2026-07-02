output "aws_region" {
  description = "AWS region used by this Terraform stack."
  value       = var.aws_region
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID used by the EKS cluster and AWS Load Balancer Controller."
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "ECR repository URL for the application image."
  value       = module.ecr.repository_url
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by NAT Gateways and public ALBs."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the EKS worker node group."
  value       = module.vpc.private_subnet_ids
}

output "postgres_secret_name" {
  description = "AWS Secrets Manager secret name used by External Secrets Operator."
  value       = module.secrets_manager.postgres_secret_name
}

output "postgres_secret_arn" {
  description = "AWS Secrets Manager secret ARN used by External Secrets Operator."
  value       = module.secrets_manager.postgres_secret_arn
}

output "external_secrets_role_arn" {
  description = "IAM role ARN for the External Secrets Operator service account."
  value       = module.eks.external_secrets_role_arn
}

output "aws_load_balancer_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller service account."
  value       = module.eks.aws_load_balancer_controller_role_arn
}
