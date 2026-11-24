variable "aws_region" {
  description = "Region for the whole store."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Address range for the VPC. 65,536 addresses; EKS gives every pod a VPC IP, so leave room."
  type        = string
  default     = "10.40.0.0/16"
}

variable "nat_gateway_mode" {
  description = "single (about $33 a month, one AZ of risk) in phase 2; per_az in phase 5."
  type        = string
  default     = "single"
}
