output "zone_id" {
  value = module.zone.zone_id
}

output "domain_name" {
  value = var.domain_name
}

output "name_servers" {
  value = module.zone.name_servers
}

output "acm_certificate_arn" {
  value = module.acm.certificate_arn
}

output "ses_identity_arn" {
  value = module.ses.identity_arn
}
