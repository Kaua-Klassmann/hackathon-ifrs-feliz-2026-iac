module "zone" {
  source = "../../../modules/route53-zone"

  domain_name = var.domain_name

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

module "acm" {
  source = "../../../modules/acm"

  domain_name = var.domain_name
  zone_id     = module.zone.zone_id

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

module "ses" {
  source = "../../../modules/ses"

  domain_name  = var.domain_name
  zone_id      = module.zone.zone_id
  dmarc_policy = var.dmarc_policy

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
