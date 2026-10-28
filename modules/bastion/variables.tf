variable "name" {
  description = "Name/identifier prefix for the bastion instance and related resources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Private subnet ID (needs a NAT route so the SSM agent can reach the SSM endpoints)"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t4g.nano"
}

variable "root_volume_size" {
  type    = number
  default = 8
}

variable "rds_security_group_id" {
  description = "RDS security group to open for the bastion"
  type        = string
}

variable "rds_port" {
  type    = number
  default = 5432
}

variable "redis_security_group_id" {
  description = "ElastiCache security group to open for the bastion"
  type        = string
}

variable "redis_port" {
  type    = number
  default = 6379
}

variable "tags" {
  type    = map(string)
  default = {}
}
