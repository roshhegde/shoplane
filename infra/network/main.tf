# Stack 2 of 4 (destroyed after each lab): the VPC across two Availability Zones.
#
#   public subnets  (10.40.0.0/24, 10.40.1.0/24)  ALB, NAT gateway
#   private subnets (10.40.16.0/20, 10.40.32.0/20) EKS nodes and pods, RDS
#
# Private subnets are /20 (4,096 addresses) because the VPC CNI gives each pod
# its own VPC IP. They reach the internet (ECR, AWS APIs) through one NAT
# gateway; nothing on the internet can open a connection to them.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source = "git::https://github.com/roshhegde/tfmodules.git//modules/vpc?ref=v1.1.0"

  name     = "shoplane"
  vpc_cidr = var.vpc_cidr
  azs      = local.azs

  public_subnet_cidrs  = [cidrsubnet(var.vpc_cidr, 8, 0), cidrsubnet(var.vpc_cidr, 8, 1)]
  private_subnet_cidrs = [cidrsubnet(var.vpc_cidr, 4, 1), cidrsubnet(var.vpc_cidr, 4, 2)]
  nat_gateway_mode     = var.nat_gateway_mode

  # The AWS Load Balancer Controller puts internet-facing ALBs in subnets
  # tagged role/elb and internal ones in subnets tagged role/internal-elb.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
