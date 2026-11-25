# Stack 1 of 4: things that stay up between labs and cost (almost) nothing.
#   - S3 bucket for Terraform state of every stack
#   - IAM role GitHub Actions assumes through OIDC (no access keys anywhere)
#   - ECR repository for the catalog image
#   - $20 monthly budget alert

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  name       = "shoplane"
}

# ---------------------------------------------------------- Terraform state --

module "state_bucket" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/s3-bucket?ref=v1.1.0"

  bucket_name = "${local.name}-tfstate-${local.account_id}"
  versioning  = true
}

# ------------------------------------------------- Container image registry --

module "catalog_repo" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/ecr-repository?ref=v1.1.0"

  name                 = "${local.name}/catalog"
  image_tag_mutability = "IMMUTABLE" # every image is tagged with its git SHA
  scan_on_push         = true
  max_image_count      = 10
}

# -------------------------------------------- GitHub Actions deploy role --
# GitHub signs a short-lived OIDC token for each workflow run. AWS STS checks
# the signature and the "sub" claim, then hands back 1-hour credentials for
# this role. Only main and the "lab" environment of this repo are trusted.

module "github_deploy" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/iam-github-oidc?ref=v1.1.0"

  role_name            = "${local.name}-github-deploy"
  github_repository    = var.github_repo
  create_oidc_provider = var.create_oidc_provider
  oidc_provider_arn    = var.create_oidc_provider ? null : "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  subjects = [
    "repo:${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_repo}:environment:lab",
  ]

  # Phase 2 builds a VPC, EKS, RDS and CloudFront, which touch dozens of
  # services. PowerUserAccess covers everything except IAM; the inline policy
  # adds IAM, limited to roles named shoplane-*. Phase 4 narrows this further.
  policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]

  inline_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManageShoplaneRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy", "iam:PutRolePolicy", "iam:GetRolePolicy",
          "iam:DeleteRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListInstanceProfilesForRole",
          "iam:PassRole",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${local.name}-*"
      },
      {
        Sid      = "ServiceLinkedRoles"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::${local.account_id}:role/aws-service-role/*"
      },
      {
        Sid      = "ReadOidcProvider"
        Effect   = "Allow"
        Action   = ["iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"]
        Resource = "*"
      },
    ]
  })
}

# ------------------------------------------------------------ Billing alert --

module "monthly_budget" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/budget?ref=v1.1.0"

  name                          = "${local.name}-monthly"
  limit_amount_usd              = var.monthly_budget_usd
  alert_emails                  = [var.budget_email]
  actual_thresholds_percent     = [50, 100]
  forecasted_thresholds_percent = [100]
}
