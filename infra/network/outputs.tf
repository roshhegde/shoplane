output "vpc_id" {
  description = "ID of the Shoplane VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR of the Shoplane VPC."
  value       = module.vpc.vpc_cidr
}

output "azs" {
  description = "The two Availability Zones in use."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnets, one per AZ."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnets, one per AZ."
  value       = module.vpc.private_subnet_ids
}

output "nat_public_ips" {
  description = "Outbound traffic from the private subnets comes from these IPs."
  value       = module.vpc.nat_public_ips
}
