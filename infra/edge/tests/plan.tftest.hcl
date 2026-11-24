# Offline test with a mocked AWS provider.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" { defaults = { json = "{}" } }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_lb" { defaults = { dns_name = "shoplane-alb-1.us-east-1.elb.amazonaws.com" } }
  mock_resource "aws_cloudfront_distribution" {
    defaults = { arn = "arn:aws:cloudfront::123456789012:distribution/E1", domain_name = "d111.cloudfront.net" }
  }
  mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::shoplane-storefront-123456789012" } }
}

run "with_api_origin" {
  command = apply

  assert {
    condition     = output.storefront_url == "https://d111.cloudfront.net"
    error_message = "Unexpected storefront URL."
  }
}

run "storefront_only" {
  command = apply

  variables {
    enable_api_origin = false
  }
}
