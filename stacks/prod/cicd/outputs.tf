output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "iac_role_arn" {
  value = module.iac_role.role_arn
}

output "api_role_arn" {
  value = module.api_role.role_arn
}

output "landing_role_arn" {
  value = module.landing_role.role_arn
}
