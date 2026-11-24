output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "db_host" {
  description = "Postgres hostname (private, reachable only from the VPC)."
  value       = module.db.address
}

output "db_name" {
  description = "Database name."
  value       = module.db.db_name
}

output "db_secret_arn" {
  description = "Secrets Manager secret with the database user name and password."
  value       = module.db.master_user_secret_arn
}

output "catalog_image_repository" {
  description = "ECR repository the catalog image is pulled from."
  value       = data.terraform_remote_state.foundation.outputs.catalog_repository_url
}

output "catalog_role_arn" {
  description = "IAM role the catalog pods receive through Pod Identity."
  value       = module.eks.pod_identity_role_arns["catalog"]
}
