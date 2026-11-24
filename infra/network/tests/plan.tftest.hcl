# Offline test: a mocked AWS provider, so no account or credentials are needed.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
}

run "two_azs_one_nat" {
  command = apply

  assert {
    condition     = length(output.public_subnet_ids) == 2 && length(output.private_subnet_ids) == 2
    error_message = "Expected one public and one private subnet in each of two AZs."
  }

  assert {
    condition     = length(output.nat_public_ips) == 1
    error_message = "Phase 2 uses a single NAT gateway."
  }
}
