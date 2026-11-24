# Stack 4 of 4: the front door. One CloudFront URL serves both
#   /*      the storefront (static files in a private S3 bucket), cached at the edge
#   /api/*  the catalog service, forwarded uncached to the ALB the Ingress created
# so the browser only ever talks to one HTTPS origin and needs no CORS.
#
# Apply this after the catalog is deployed, because the ALB only exists once the
# AWS Load Balancer Controller has processed the Ingress.

data "aws_caller_identity" "current" {}

data "aws_lb" "catalog" {
  count = var.enable_api_origin ? 1 : 0
  name  = var.alb_name
}

module "storefront_bucket" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/s3-bucket?ref=v1.1.0"

  bucket_name   = "shoplane-storefront-${data.aws_caller_identity.current.account_id}"
  versioning    = false
  force_destroy = true # the site is rebuilt from git, so nothing here is precious

  # Only this CloudFront distribution may read objects (Origin Access Control).
  # The bucket itself stays fully private.
  attach_policy = true
  policy_json   = module.cdn.bucket_policy_json
}

module "cdn" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/cloudfront?ref=v1.1.0"

  name                           = "shoplane"
  comment                        = "Shoplane storefront and API"
  s3_bucket_name                 = module.storefront_bucket.bucket_name
  s3_bucket_regional_domain_name = module.storefront_bucket.bucket_regional_domain_name

  # CloudFront to ALB is plain HTTP inside AWS's network for now; viewers still
  # get HTTPS. Phase 4 adds a certificate on the ALB and locks it to CloudFront.
  custom_origins = var.enable_api_origin ? [{
    origin_id     = "catalog-alb"
    domain_name   = data.aws_lb.catalog[0].dns_name
    path_patterns = ["/api/*"]
  }] : []
}
