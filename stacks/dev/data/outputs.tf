output "rds_endpoint" {
  value = module.rds.endpoint
}

output "rds_security_group_id" {
  value = module.rds.security_group_id
}

output "rds_master_user_secret_arn" {
  value = module.rds.master_user_secret_arn
}

output "rds_port" {
  value = module.rds.port
}

output "rds_master_username" {
  value = module.rds.master_username
}

output "rds_db_name" {
  value = module.rds.db_name
}

output "rds_identifier" {
  value = module.rds.identifier
}

output "redis_endpoint" {
  value = module.elasticache.primary_endpoint_address
}

output "redis_security_group_id" {
  value = module.elasticache.security_group_id
}

output "redis_port" {
  value = module.elasticache.port
}

output "redis_replication_group_id" {
  value = module.elasticache.replication_group_id
}

output "bastion_instance_id" {
  value = module.bastion.instance_id
}

output "bastion_security_group_id" {
  value = module.bastion.security_group_id
}
