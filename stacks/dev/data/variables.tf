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
  default = "dev"
}

variable "db_name" {
  type    = string
  default = "hackathon"
}

variable "rds_multi_az" {
  type    = bool
  default = false
}

variable "elasticache_multi_az" {
  type    = bool
  default = false
}
