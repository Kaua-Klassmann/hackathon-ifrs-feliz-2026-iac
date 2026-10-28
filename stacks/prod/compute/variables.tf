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

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "desired_count" {
  type    = number
  default = 2
}

variable "enable_autoscaling" {
  type    = bool
  default = true
}

variable "min_capacity" {
  type    = number
  default = 2
}

variable "max_capacity" {
  type    = number
  default = 8
}

variable "cpu_target_value" {
  type    = number
  default = 60
}

variable "app_payload_max_size_mb" {
  type    = number
  default = 2
}

variable "database_schema" {
  type    = string
  default = "public"
}

variable "database_min_connections" {
  type    = number
  default = 2
}

variable "database_max_connections" {
  type    = number
  default = 10
}

variable "image_tag" {
  description = "Image tag for the initial (bootstrap) task definition — CodeDeploy takes over on subsequent deploys"
  type        = string
  default     = "bootstrap"
}
