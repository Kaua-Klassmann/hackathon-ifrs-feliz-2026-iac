resource "aws_amplify_app" "this" {
  name         = var.name
  repository   = var.repository
  access_token = var.access_token
  platform     = "WEB_COMPUTE"

  environment_variables = var.environment_variables

  tags = var.tags
}

resource "aws_amplify_branch" "this" {
  app_id      = aws_amplify_app.this.id
  branch_name = var.branch_name
  framework   = "Next.js - SSR"
  stage       = var.stage

  enable_auto_build = true
}

# No manual Route53 records here: when the hosted zone lives in the same AWS account,
# Amplify detects it and manages the certificate-verification and subdomain DNS records
# itself (confirmed by CreateDomainAssociation failing with "already exists" when this
# module also tried to create them).
resource "aws_amplify_domain_association" "this" {
  app_id                = aws_amplify_app.this.id
  domain_name           = var.zone_domain
  wait_for_verification = true

  sub_domain {
    branch_name = aws_amplify_branch.this.branch_name
    prefix      = var.subdomain_prefix
  }
}
