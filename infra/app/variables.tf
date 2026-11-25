variable "aws_region" {
  description = "Region for the whole store."
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Terraform state bucket from the aws-foundation stack, used to read the other stacks' outputs."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "node_instance_types" {
  description = "Graviton instance types for the Spot node group. Listing more than one gives Spot more pools to draw from."
  type        = list(string)
  default     = ["t4g.medium"]
}

variable "cluster_admin_arns" {
  description = "IAM users or roles (keyed by a label) that get cluster admin, besides the GitHub deploy role. Include whoever runs terraform locally, or Helm can't install the controller."
  type        = map(string)
  default     = {}
}

variable "api_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. IAM still decides who gets in."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "lb_controller_chart_version" {
  description = "Helm chart version of the AWS Load Balancer Controller (chart 1.14.x ships controller v2.14.x)."
  type        = string
  default     = "1.14.0"
}
