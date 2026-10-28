data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/networking/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "alerting" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/alerting/terraform.tfstate"
    region = "us-east-1"
  }
}

module "rds" {
  source = "../../../modules/rds"

  name       = "${var.project}-${var.environment}-rds"
  vpc_id     = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.networking.outputs.isolated_subnets

  db_name  = var.db_name
  multi_az = var.rds_multi_az

  sns_topic_arn = data.terraform_remote_state.alerting.outputs.sns_topic_arn

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

module "elasticache" {
  source = "../../../modules/elasticache"

  name       = "${var.project}-${var.environment}-cache"
  vpc_id     = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.networking.outputs.isolated_subnets

  multi_az = var.elasticache_multi_az

  sns_topic_arn = data.terraform_remote_state.alerting.outputs.sns_topic_arn

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

module "bastion" {
  source = "../../../modules/bastion"

  name      = "${var.project}-${var.environment}-bastion"
  vpc_id    = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_id = data.terraform_remote_state.networking.outputs.private_subnets[0]

  rds_security_group_id   = module.rds.security_group_id
  rds_port                = module.rds.port
  redis_security_group_id = module.elasticache.security_group_id
  redis_port              = module.elasticache.port

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
