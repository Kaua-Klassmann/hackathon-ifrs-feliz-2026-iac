module "vpc" {
  source = "../../../modules/vpc"

  name               = "${var.project}-${var.environment}-vpc"
  cidr_block         = var.vpc_cidr_block
  az_count           = var.az_count
  single_nat_gateway = var.single_nat_gateway

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}