variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "hackathon"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "db_name" {
  type    = string
  default = "hackathon"
}

variable "rds_multi_az" {
  type    = bool
  default = true
}

variable "elasticache_multi_az" {
  type    = bool
  default = true
}

variable "backup_dr_region" {
  type    = string
  default = "us-west-2"
}

variable "rds_backup_retention_period" {
  type    = number
  default = 7
}
