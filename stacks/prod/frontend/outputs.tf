output "landing_url" {
  value = "https://${module.landing.distribution_domain_name}"
}

output "landing_bucket_name" {
  value = module.landing.bucket_name
}

output "landing_distribution_id" {
  value = module.landing.distribution_id
}

output "app_url" {
  value = "https://${module.app.custom_domain}"
}

output "amplify_app_id" {
  value = module.app.app_id
}
