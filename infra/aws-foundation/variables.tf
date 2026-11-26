variable "aws_region" {
  description = "Region for the whole store."
  type        = string
  default     = "us-east-1"
}

variable "github_repo" {
  description = "owner/name of the GitHub repository allowed to deploy."
  type        = string
  default     = "roshhegde/shoplane"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. An account can have only one, and the serverless job tracker already created it, so this defaults to false."
  type        = bool
  default     = false
}

variable "budget_email" {
  description = "Email that receives billing alerts."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly budget for the AWS side of Shoplane."
  type        = string
  default     = "20"
}
