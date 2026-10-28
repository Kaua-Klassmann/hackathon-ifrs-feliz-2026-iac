output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  value = module.vpc.vpc_cidr_block
}

output "public_subnets" {
  value = module.vpc.public_subnet_ids
}

output "private_subnets" {
  value = module.vpc.private_subnet_ids
}

output "isolated_subnets" {
  value = module.vpc.isolated_subnet_ids
}

output "availability_zones" {
  value = module.vpc.availability_zones
}
