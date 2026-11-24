variable "aws_region" {
  description = "Region for the whole store."
  type        = string
  default     = "us-east-1"
}

variable "alb_name" {
  description = "Name the catalog Ingress gives its ALB (alb.ingress.kubernetes.io/load-balancer-name)."
  type        = string
  default     = "shoplane-alb"
}

variable "enable_api_origin" {
  description = "Route /api/* to the ALB. Set false to serve only the storefront when no lab is running (the ALB doesn't exist then)."
  type        = bool
  default     = true
}
