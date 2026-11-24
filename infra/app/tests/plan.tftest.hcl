# Offline test: mocked AWS and Helm providers plus fake outputs from the other
# stacks, so it checks the wiring (no cycles, known for_each keys) for free.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" { defaults = { json = "{}" } }
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn                   = "arn:aws:eks:us-east-1:123456789012:cluster/shoplane"
      certificate_authority = [{ data = "Zm9v" }]
    }
  }
  mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/shoplane-x" } }
  mock_resource "aws_db_instance" {
    defaults = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds", kms_key_id = "k", secret_status = "active" }]
    }
  }
}

mock_provider "helm" {}

override_data {
  target = data.terraform_remote_state.foundation
  values = {
    outputs = {
      github_role_arn        = "arn:aws:iam::123456789012:role/shoplane-github-deploy"
      catalog_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/shoplane/catalog"
    }
  }
}

override_data {
  target = data.terraform_remote_state.network
  values = {
    outputs = {
      vpc_id             = "vpc-123"
      private_subnet_ids = ["subnet-a", "subnet-b"]
    }
  }
}

variables {
  state_bucket       = "shoplane-tfstate-123456789012"
  cluster_admin_arns = { rosh = "arn:aws:iam::123456789012:user/rosh" }
}

run "app_stack" {
  command = apply

  assert {
    condition     = length(module.eks.pod_identity_role_arns) == 2
    error_message = "Expected Pod Identity roles for the LB controller and the catalog."
  }
}
