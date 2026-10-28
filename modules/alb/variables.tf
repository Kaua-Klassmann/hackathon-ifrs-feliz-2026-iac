variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "certificate_arn" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "enable_deletion_protection" {
  description = "Prevents the ALB from being deleted via terraform destroy or the console"
  type        = bool
  default     = false
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications. Null disables alarms."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
