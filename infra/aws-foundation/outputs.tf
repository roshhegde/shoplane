output "state_bucket" {
  description = "Bucket that holds Terraform state. Put it in infra/backend.hcl and in the TF_STATE_BUCKET repository variable."
  value       = module.state_bucket.bucket_name
}

output "github_role_arn" {
  description = "Role GitHub Actions assumes. Put it in the AWS_ROLE_ARN repository variable."
  value       = module.github_deploy.role_arn
}

output "catalog_repository_url" {
  description = "ECR repository for the catalog image."
  value       = module.catalog_repo.repository_url
}
