output "storefront_url" {
  description = "Open this in a browser."
  value       = "https://${module.cdn.domain_name}"
}

output "storefront_bucket" {
  description = "Bucket the storefront files are synced to."
  value       = module.storefront_bucket.bucket_name
}

output "distribution_id" {
  description = "CloudFront distribution ID, for cache invalidations."
  value       = module.cdn.distribution_id
}
