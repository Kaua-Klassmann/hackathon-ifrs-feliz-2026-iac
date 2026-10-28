data "terraform_remote_state" "prod_dns" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "prod/dns/terraform.tfstate"
    region = "us-east-1"
  }
}

module "zone" {
  source = "../../../modules/route53-zone"

  domain_name = var.domain_name

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

resource "aws_route53_record" "delegation" {
  zone_id = data.terraform_remote_state.prod_dns.outputs.zone_id
  name    = var.domain_name
  type    = "NS"
  ttl     = 172800
  records = module.zone.name_servers
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
