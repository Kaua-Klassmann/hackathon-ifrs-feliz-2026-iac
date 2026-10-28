data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "4o4-hackathon-tfstate"
    key    = "dev/dns/terraform.tfstate"
    region = "us-east-1"
  }
}

module "landing" {
  source = "../../../modules/static-site"

  name            = "${var.project}-${var.environment}-landing"
  domain_name     = data.terraform_remote_state.dns.outputs.domain_name
  certificate_arn = data.terraform_remote_state.dns.outputs.acm_certificate_arn
  zone_id         = data.terraform_remote_state.dns.outputs.zone_id

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

module "app" {
  source = "../../../modules/amplify-app"

  name         = "${var.project}-${var.environment}-app"
  repository   = var.github_repository
  access_token = var.github_access_token
  branch_name  = "develop"
  stage        = "DEVELOPMENT"

  zone_domain      = data.terraform_remote_state.dns.outputs.domain_name
  subdomain_prefix = "app"

  environment_variables = {
    NEXT_PUBLIC_APP_ENV = "dev"
  }

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}
