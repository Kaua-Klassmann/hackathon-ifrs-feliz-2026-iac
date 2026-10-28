output "alb_dns_name" {
  value = module.alb.dns_name
}

output "ecr_repository_url" {
  value = data.terraform_remote_state.shared_ecr.outputs.repository_url
}

output "ecr_repository_arn" {
  value = data.terraform_remote_state.shared_ecr.outputs.repository_arn
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "api_url" {
  value = "https://${aws_route53_record.api.name}"
}

output "codedeploy_application_name" {
  value = module.codedeploy.app_name
}

output "codedeploy_deployment_group_name" {
  value = module.codedeploy.deployment_group_name
}
