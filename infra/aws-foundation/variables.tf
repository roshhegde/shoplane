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

variable "github_repo_with_ids" {
  description = "The same repository written owner@owner_id/name@repo_id. GitHub puts this form in the token's sub claim when the account uses immutable IDs in OIDC subjects; it is trusted alongside the plain form."
  type        = string
  default     = "roshhegde@208154472/shoplane@1470806548"
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
